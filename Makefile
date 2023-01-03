PLATFORM_IOS = iOS Simulator,name=iPhone 11 Pro Max

default: test-all

test-all: CONFIG=debug test-library
	CONFIG=release test-library

test-library:
	for platform in "$(PLATFORM_IOS)"; do \
		xcodebuild test \
                        -configuration=$CONFIG \
			-scheme klaviyo-swift-sdk \
			-destination platform="$$platform" || exit 1; \
	done;
