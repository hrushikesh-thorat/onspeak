import AppKit
import Combine
import Foundation

enum OnSpeakLinks {
    static let repository = URL(string: "https://github.com/hrushikesh-thorat/OnSpeak")!
}

struct AppSemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }

        let withoutBuildMetadata = value.split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
        let versionParts = withoutBuildMetadata
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        let coreParts = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)

        guard coreParts.count == 3,
              let major = Int(coreParts[0]),
              let minor = Int(coreParts[1]),
              let patch = Int(coreParts[2]),
              major >= 0, minor >= 0, patch >= 0 else {
            return nil
        }

        let prerelease: [String]
        if versionParts.count == 2 {
            prerelease = versionParts[1]
                .split(separator: ".", omittingEmptySubsequences: false)
                .map(String.init)
            guard !prerelease.isEmpty, prerelease.allSatisfy({ !$0.isEmpty }) else {
                return nil
            }
        } else {
            prerelease = []
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    static func < (lhs: AppSemanticVersion, rhs: AppSemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for index in 0..<min(lhs.prerelease.count, rhs.prerelease.count) {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }

            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left < right
            }
        }

        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct AppUpdateRelease: Equatable {
    let version: String
    let tag: String
    let pageURL: URL

    func isNewer(than currentVersion: String) -> Bool {
        guard let current = AppSemanticVersion(currentVersion),
              let latest = AppSemanticVersion(tag) else {
            return false
        }
        return current < latest
    }
}

struct GitHubLatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let isDraft: Bool
    let isPrerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }

    var appRelease: AppUpdateRelease? {
        guard !isDraft, !isPrerelease, let parsedVersion = AppSemanticVersion(tagName) else {
            return nil
        }
        return AppUpdateRelease(
            version: "\(parsedVersion.major).\(parsedVersion.minor).\(parsedVersion.patch)",
            tag: tagName,
            pageURL: htmlURL
        )
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    private static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/hrushikesh-thorat/OnSpeak/releases/latest"
    )!

    @Published private(set) var availableRelease: AppUpdateRelease?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckMessage: String?

    var onAutomaticUpdateAvailable: ((AppUpdateRelease) -> Bool)?

    private var periodicTimer: Timer?
    private let notifiedVersionKey = "update_notified_version"
    private let automaticCheckInterval: TimeInterval = 12 * 60 * 60

    private init() {}

    var updateAvailable: Bool {
        availableRelease != nil
    }

    func startAutomaticChecks() {
        guard periodicTimer == nil, isReleaseBuild else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await self?.checkForUpdates(userInitiated: false)
        }

        let timer = Timer.scheduledTimer(withTimeInterval: automaticCheckInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates(userInitiated: false)
            }
        }
        timer.tolerance = 15 * 60
        periodicTimer = timer
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        if userInitiated {
            lastCheckMessage = nil
        }
        defer { isChecking = false }

        do {
            var request = URLRequest(url: Self.latestReleaseAPIURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("OnSpeak-Update-Checker", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw UpdateCheckError.invalidResponse
            }

            let githubRelease = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
            guard let release = githubRelease.appRelease else {
                throw UpdateCheckError.invalidRelease
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            if release.isNewer(than: currentVersion) {
                availableRelease = release
                if userInitiated {
                    lastCheckMessage = "OnSpeak \(release.version) is available."
                } else {
                    presentAutomaticNoticeIfNeeded(for: release)
                }
            } else {
                availableRelease = nil
                if userInitiated {
                    lastCheckMessage = "You’re using the latest version."
                }
            }
        } catch {
            if userInitiated {
                lastCheckMessage = "Couldn’t check for updates. Try again shortly."
            }
        }
    }

    func openAvailableRelease() {
        guard let url = availableRelease?.pageURL else { return }
        NSWorkspace.shared.open(url)
    }

    private var isReleaseBuild: Bool {
        guard let buildTag = Bundle.main.infoDictionary?["OnSpeakBuildTag"] as? String else {
            return false
        }
        return buildTag.hasPrefix("v") && AppSemanticVersion(buildTag) != nil
    }

    private func presentAutomaticNoticeIfNeeded(for release: AppUpdateRelease) {
        guard UserDefaults.standard.string(forKey: notifiedVersionKey) != release.tag else {
            return
        }
        if onAutomaticUpdateAvailable?(release) == true {
            UserDefaults.standard.set(release.tag, forKey: notifiedVersionKey)
        }
    }
}

private enum UpdateCheckError: Error {
    case invalidResponse
    case invalidRelease
}
