APP_NAME ?= OnSpeak
BUNDLE_ID ?= com.rushatpeace.onspeak
BUILD_TAG ?= local
DEV_APP_NAME = onspeak-dev
DEV_BUNDLE_ID = com.rushatpeace.onspeak.dev
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CODESIGN_IDENTITY ?= -
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
empty :=
space := $(empty) $(empty)
APP_EXECUTABLE = $(MACOS_DIR)/$(APP_NAME)
APP_EXECUTABLE_TARGET := $(subst $(space),\ ,$(APP_EXECUTABLE))

SOURCES = $(shell find Sources -name '*.swift' -type f | LC_ALL=C sort)
TEST_RUNNER = $(BUILD_DIR)/OnSpeakTests
EVAL_RUNNER = $(BUILD_DIR)/OnSpeakDynamicCleanupEval
# The eval mirrors production: each spoken input passes through the
# deterministic TranscriptTidier.tidy before reaching the model, so the tidier
# source is compiled into the eval runner. It compiles standalone (the `make
# test` runner already builds it that way), so no extra dependencies are pulled.
EVAL_SOURCES = $(shell find Sources/DynamicCleanup -name '*.swift' -type f | LC_ALL=C sort) Sources/TranscriptTidier.swift
RESOURCES = $(CONTENTS)/Resources
ARCH ?= $(shell uname -m)

ICON_SOURCE = Resources/AppIcon-Source.png
ICON_ICNS = Resources/AppIcon.icns

.PHONY: all clean run dev dev-run icon dmg codesign-dmg notarize test eval

all: $(APP_EXECUTABLE_TARGET)

$(APP_EXECUTABLE_TARGET): $(SOURCES) Info.plist $(ICON_ICNS) Resources/MenuBarIcon.svg
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
ifeq ($(ARCH),universal)
	swiftc \
		-parse-as-library \
		-o "$(MACOS_DIR)/$(APP_NAME)-arm64" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target arm64-apple-macosx26.0 \
		$(SOURCES)
	swiftc \
		-parse-as-library \
		-o "$(MACOS_DIR)/$(APP_NAME)-x86_64" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target x86_64-apple-macosx26.0 \
		$(SOURCES)
	lipo -create -output "$(MACOS_DIR)/$(APP_NAME)" \
		"$(MACOS_DIR)/$(APP_NAME)-arm64" \
		"$(MACOS_DIR)/$(APP_NAME)-x86_64"
	@rm "$(MACOS_DIR)/$(APP_NAME)-arm64" "$(MACOS_DIR)/$(APP_NAME)-x86_64"
else
	swiftc \
		-parse-as-library \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx26.0 \
		$(SOURCES)
endif
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleDisplayName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@plutil -replace OnSpeakBuildTag -string "$(BUILD_TAG)" "$(CONTENTS)/Info.plist"
	@cp $(ICON_ICNS) "$(RESOURCES)/AppIcon.icns"
	@cp Resources/MenuBarIcon.svg "$(RESOURCES)/MenuBarIcon.svg"
	@plutil -replace NSMicrophoneUsageDescription -string "$(APP_NAME) needs microphone access to transcribe your speech." "$(CONTENTS)/Info.plist"
	@plutil -replace NSSpeechRecognitionUsageDescription -string "$(APP_NAME) needs speech recognition to convert your voice to text." "$(CONTENTS)/Info.plist"
	@plutil -replace NSAccessibilityUsageDescription -string "$(APP_NAME) needs accessibility access to detect the text cursor position and paste transcribed text." "$(CONTENTS)/Info.plist"
	@codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" --entitlements OnSpeak.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

test: $(TEST_RUNNER)
	@$(TEST_RUNNER)

$(TEST_RUNNER): Sources/TranscriptTidier.swift Sources/ShortcutCore/ShortcutMatcher.swift Sources/ShortcutCore/ShortcutModels.swift Sources/DynamicCleanup/DynamicCleanupGuard.swift Sources/Dictionary/DictionaryTermLearner.swift Sources/Dictionary/DictionaryStore.swift Sources/LiveTranscriptComposer.swift Sources/LiveTranscriptSessionSupport.swift Sources/UpdateChecker.swift Tests/TestRunner.swift Tests/ShortcutTests.swift Tests/TranscriptTidierTests.swift Tests/DynamicCleanupGuardTests.swift Tests/DictionaryTermLearnerTests.swift Tests/DictionaryStoreTests.swift Tests/LiveTranscriptComposerTests.swift Tests/LiveTranscriptSessionSupportTests.swift Tests/UpdateCheckerTests.swift
	@mkdir -p "$(BUILD_DIR)"
	swiftc \
		-parse-as-library \
		-o "$(TEST_RUNNER)" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx26.0 \
		Sources/TranscriptTidier.swift Tests/TestRunner.swift Tests/TranscriptTidierTests.swift \
		Sources/ShortcutCore/ShortcutMatcher.swift Sources/ShortcutCore/ShortcutModels.swift Tests/ShortcutTests.swift \
		Sources/DynamicCleanup/DynamicCleanupGuard.swift Tests/DynamicCleanupGuardTests.swift \
		Sources/Dictionary/DictionaryTermLearner.swift Sources/Dictionary/DictionaryStore.swift Tests/DictionaryTermLearnerTests.swift Tests/DictionaryStoreTests.swift \
		Sources/LiveTranscriptComposer.swift Tests/LiveTranscriptComposerTests.swift \
		Sources/LiveTranscriptSessionSupport.swift Tests/LiveTranscriptSessionSupportTests.swift \
		Sources/UpdateChecker.swift Tests/UpdateCheckerTests.swift

# Manual golden-case eval for the on-device dynamic-cleanup post-processor
# (spec 001, "Testing" section). A tuning tool, not a CI gate: it runs real
# transcripts through Apple's on-device Foundation Models and prints a
# pass/diff table. Requires macOS 26 with Apple Intelligence enabled; when
# unavailable the runner explains why and exits 0.
eval: $(EVAL_RUNNER)
	@$(EVAL_RUNNER)

$(EVAL_RUNNER): $(EVAL_SOURCES) Tests/DynamicCleanupEval.swift
	@mkdir -p "$(BUILD_DIR)"
	swiftc \
		-parse-as-library \
		-o "$(EVAL_RUNNER)" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx26.0 \
		$(EVAL_SOURCES) Tests/DynamicCleanupEval.swift

icon: $(ICON_ICNS)

$(ICON_ICNS): $(ICON_SOURCE) Scripts/generate-icns.swift
	@swift Scripts/generate-icns.swift $< $@
	@echo "Generated $@"

dmg: all
	@rm -f "$(BUILD_DIR)/$(APP_NAME).dmg"
	@rm -rf $(BUILD_DIR)/dmg-staging
	@mkdir -p $(BUILD_DIR)/dmg-staging
	@cp -R "$(APP_BUNDLE)" $(BUILD_DIR)/dmg-staging/
	@osascript -e 'tell application "Finder" to make alias file to POSIX file "/Applications" at POSIX file "'"$$(cd $(BUILD_DIR)/dmg-staging && pwd)"'"'
	@ALIAS=$$(find $(BUILD_DIR)/dmg-staging -maxdepth 1 -not -name '*.app' -not -name '.DS_Store' -type f | head -1) && mv "$$ALIAS" "$(BUILD_DIR)/dmg-staging/Applications"
	@fileicon set "$(BUILD_DIR)/dmg-staging/Applications" /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns
	@echo "Creating DMG..."
	@create-dmg \
		--volname "$(APP_NAME)" \
		--volicon "$(ICON_ICNS)" \
		--background "Resources/dmg-background.tiff" \
		--window-pos 200 120 \
		--window-size 660 400 \
		--icon-size 128 \
		--icon "$(APP_NAME).app" 180 170 \
		--hide-extension "$(APP_NAME).app" \
		--icon "Applications" 480 170 \
		--no-internet-enable \
		"$(BUILD_DIR)/$(APP_NAME).dmg" \
		"$(BUILD_DIR)/dmg-staging"
	@rm -rf $(BUILD_DIR)/dmg-staging
	@echo "Created $(BUILD_DIR)/$(APP_NAME).dmg"

codesign-dmg: dmg
	codesign --force --sign "$(CODESIGN_IDENTITY)" "$(BUILD_DIR)/$(APP_NAME).dmg"

notarize:
	xcrun notarytool submit "$(BUILD_DIR)/$(APP_NAME).dmg" \
		--keychain-profile "$(NOTARIZE_PROFILE)" --wait
	xcrun stapler staple "$(BUILD_DIR)/$(APP_NAME).dmg"

clean:
	rm -rf $(BUILD_DIR)

run: all
	open "$(APP_BUNDLE)"

DEV_BUILD_TAG = dev-$(shell git rev-parse --short HEAD 2>/dev/null || echo nogit)$(shell git diff --quiet 2>/dev/null || echo -dirty)-$(shell date +%Y%m%d.%H%M)

# Dev signing: macOS ties the Accessibility grant to the app's code signature,
# and an ad-hoc signature changes on every rebuild, so the grant would need
# re-approval each build. A persistent self-signed "onspeak-dev-signing"
# code-signing certificate (create once in Keychain Access) keeps the identity
# stable across rebuilds; when absent, fall back to ad-hoc.
DEV_CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q "onspeak-dev-signing" && echo onspeak-dev-signing || echo -)

dev:
	@$(MAKE) APP_NAME="$(DEV_APP_NAME)" BUNDLE_ID="$(DEV_BUNDLE_ID)" BUILD_TAG="$(DEV_BUILD_TAG)" CODESIGN_IDENTITY="$(DEV_CODESIGN_IDENTITY)" all

dev-run: dev
	open "$(BUILD_DIR)/$(DEV_APP_NAME).app"
