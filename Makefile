CONFIG = debug
XCODE = 15.2
# Simulator runtime *major family* to test against. Default is for local runs; CI
# overrides per matrix row (macos-14 -> iOS 17, macos-15 -> iOS 18, macos-26 -> iOS 26)
# so each runner tests its own OS generation. Resolved to the newest installed minor
# (e.g. "iOS 26" -> "iOS 26.5") below, so the choice is deterministic when several
# minors are installed. The test-library guard fails loudly if none is installed.
# Bump the CI majors in .github/workflows/swift.yml as runner images move forward.
IOS_RUNTIME = iOS 18
IOS_RUNTIME_RESOLVED = $(call newest_ios_runtime,$(IOS_RUNTIME))
IOS_UDID = $(call udid_for,$(IOS_RUNTIME_RESOLVED),iPhone \d\+ Pro [^M])
PLATFORM_IOS = iOS Simulator,id=$(IOS_UDID)


default: test-all

test-all: $(MAKE) CONFIG=debug test-library
	$(MAKE) CONFIG=release test-library

test-library:
	@if [ -z "$(IOS_UDID)" ]; then \
		echo "ERROR: no '$(IOS_RUNTIME)' iPhone Pro simulator on this runner. Bump IOS_RUNTIME to an installed runtime:"; \
		xcrun simctl list runtimes; \
		exit 1; \
	fi
	for platform in "$(PLATFORM_IOS)"; do \
		env TEST_RUNNER_GITHUB_CI=$(GITHUB_CI) \
		xcodebuild test \
			-resultBundlePath TestResults-$(XCODE)-$(CONFIG) \
			-enableCodeCoverage YES \
			-configuration=$(CONFIG) \
			-scheme klaviyo-swift-sdk-Package \
			-destination platform="$$platform" \
			-test-timeouts-enabled YES \
			-default-test-execution-time-allowance 120 \
			-maximum-test-execution-time-allowance 300 || exit 1; \
	done;

define udid_for
$(shell xcrun simctl list devices available '$(1)' | grep '$(2)' | sort -r | head -1 | awk -F '[()]' '{ print $$(NF-3) }')
endef

define newest_ios_runtime
$(shell xcrun simctl list runtimes available | grep -oE '$(1)\.[0-9]+' | sort -V | tail -1)
endef
