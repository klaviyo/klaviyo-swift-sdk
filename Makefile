CONFIG = debug
XCODE = 15.2
# Pin the simulator runtime. Left unpinned, the macOS-15 runner picks its newest
# installed simulator (currently iOS 26), where Swift-concurrency code hangs under
# release optimization. iOS 18 is present on every CI runner image and passes
# consistently. Bump this as the runner images move forward.
IOS_RUNTIME = iOS 18
PLATFORM_IOS = iOS Simulator,id=$(call udid_for,$(IOS_RUNTIME),iPhone \d\+ Pro [^M])


default: test-all

test-all: $(MAKE) CONFIG=debug test-library
	$(MAKE) CONFIG=release test-library

test-library:
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
