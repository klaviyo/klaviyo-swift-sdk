CONFIG = debug
XCODE = 15.2
# Pin the simulator runtime. Left unpinned, the macOS-15 runner picks its newest
# installed simulator (currently iOS 26), where Swift-concurrency code hangs under
# release optimization. iOS 18 is installed on both the macOS-14 and macOS-15 CI
# runner images (independent of the selected Xcode — `xcode-select` does not remove
# other installed runtimes), so all matrix jobs run on it consistently. Bump this
# as the runner images move forward; the `test-library` guard below fails loudly if
# the pinned runtime is ever missing.
IOS_RUNTIME = iOS 18
IOS_UDID = $(call udid_for,$(IOS_RUNTIME),iPhone \d\+ Pro [^M])
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
