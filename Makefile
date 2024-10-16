CONFIG = debug
PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iOS,iPhone \d\+ Pro [^M])


default: test-all

test-all: $(MAKE) CONFIG=debug test-library
	$(MAKE) CONFIG=release test-library

test-library:
	for platform in "$(PLATFORM_IOS)"; do \
		xcodebuild test \
			-resultBundlePath TestResults \
			-enableCodeCoverage YES \
			-configuration=$(CONFIG) \
			-scheme klaviyo-swift-sdk-Package \
			-destination platform="$$platform" || exit 1; \
	done;

define udid_for
$(shell xcrun simctl list devices available '$(1)' | grep '$(2)' | sort -r | head -1 | awk -F '[()]' '{ print $$(NF-3) }')
endef
