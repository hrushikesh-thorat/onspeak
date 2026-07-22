import Foundation

enum UpdateCheckerTests {
    static func run() {
        expect(AppSemanticVersion("v0.5.1") == AppSemanticVersion("0.5.1"), "v prefix was not normalized")
        expect(AppSemanticVersion("0.5.10")! > AppSemanticVersion("0.5.2")!, "patch versions were compared as text")
        expect(AppSemanticVersion("0.6.0")! > AppSemanticVersion("0.5.99")!, "minor version ordering failed")
        expect(AppSemanticVersion("1.0.0")! > AppSemanticVersion("0.99.99")!, "major version ordering failed")
        expect(AppSemanticVersion("1.0.0-beta.2")! < AppSemanticVersion("1.0.0")!, "prerelease sorted after stable release")
        expect(AppSemanticVersion("1.0.0-beta.10")! > AppSemanticVersion("1.0.0-beta.2")!, "numeric prerelease ordering failed")
        expect(AppSemanticVersion("0.5") == nil, "two-part version was accepted")
        expect(AppSemanticVersion("release") == nil, "non-semantic version was accepted")

        let release = AppUpdateRelease(
            version: "0.5.2",
            tag: "v0.5.2",
            pageURL: URL(string: "https://example.com/release")!
        )
        expect(release.isNewer(than: "0.5.1"), "new release was not detected")
        expect(!release.isNewer(than: "0.5.2"), "installed release was reported as newer")
        expect(!release.isNewer(than: "0.6.0"), "older release was reported as newer")

        testGitHubReleaseDecoding()
    }

    private static func testGitHubReleaseDecoding() {
        let stableJSON = #"""
        {
            "tag_name": "v0.5.2",
            "html_url": "https://github.com/hrushikesh-thorat/OnSpeak/releases/tag/v0.5.2",
            "draft": false,
            "prerelease": false
        }
        """#.data(using: .utf8)!
        let stable = try! JSONDecoder().decode(GitHubLatestRelease.self, from: stableJSON)
        expect(stable.appRelease?.version == "0.5.2", "stable GitHub release was not decoded")
        expect(stable.appRelease?.tag == "v0.5.2", "release tag was not preserved")

        let prereleaseJSON = #"""
        {
            "tag_name": "v0.6.0-beta.1",
            "html_url": "https://github.com/hrushikesh-thorat/OnSpeak/releases/tag/v0.6.0-beta.1",
            "draft": false,
            "prerelease": true
        }
        """#.data(using: .utf8)!
        let prerelease = try! JSONDecoder().decode(GitHubLatestRelease.self, from: prereleaseJSON)
        expect(prerelease.appRelease == nil, "GitHub prerelease was offered as a stable update")

        let draftJSON = #"""
        {
            "tag_name": "v0.6.0",
            "html_url": "https://github.com/hrushikesh-thorat/OnSpeak/releases/tag/v0.6.0",
            "draft": true,
            "prerelease": false
        }
        """#.data(using: .utf8)!
        let draft = try! JSONDecoder().decode(GitHubLatestRelease.self, from: draftJSON)
        expect(draft.appRelease == nil, "GitHub draft was offered as a stable update")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if !condition() {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
