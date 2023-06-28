CONFIG = debug
PLATFORM_IOS = iOS Simulator,name=iPhone 14

default: test-all

test-all: $(MAKE) CONFIG=debug test-library
	$(MAKE) CONFIG=release test-library

test-library:
	for platform in "$(PLATFORM_IOS)"; do \
		xcodebuild test \
			-workspace=.github/package.xcworkspace \
			-configuration=$(CONFIG) \
			-scheme KlaviyoSwiftTests \
			-destination platform="$$platform" || exit 1; \
	done;
