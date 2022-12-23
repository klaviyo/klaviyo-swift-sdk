test-ios:
	set -o pipefail && \
	xcodebuild test \
		-scheme klaviyo-swift-sdk \
		-destination platform="iOS Simulator,name=iPhone 11 Pro Max,OS=13.3" \

test-all: test-ios
