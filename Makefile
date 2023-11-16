CONFIG = debug
PLATFORM_IOS = iOS Simulator,name=iPhone 14

default: test-all

test-all: $(MAKE) CONFIG=debug test-library
	$(MAKE) CONFIG=release test-library

test-library:
	for platform in "$(PLATFORM_IOS)"; do \
		xcodebuild test \
			-resultBundlePath TestResults \
			-enableCodeCoverag YES \
			-configuration=$(CONFIG) \
			-scheme klaviyo-swift-sdk-Package \
			-destination platform="$$platform" || exit 1; \
	done;
