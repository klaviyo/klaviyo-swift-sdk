CONFIG = debug
XCODE = 16.4
# Simulator runtime *major family* to test against. Default is for local runs; CI
# overrides per matrix row (macos-15 -> iOS 18, macos-26 -> iOS 26)
# so each runner tests its own OS generation. Resolved to the newest installed minor
# (e.g. "iOS 26" -> "iOS 26.5") below, so the choice is deterministic when several
# minors are installed. The test-library guard fails loudly if none is installed.
# Bump the CI majors in .github/workflows/swift.yml as runner images move forward.
IOS_RUNTIME = iOS 18
IOS_RUNTIME_RESOLVED = $(call newest_ios_runtime,$(IOS_RUNTIME))
IOS_UDID = $(call udid_for,$(IOS_RUNTIME_RESOLVED),iPhone \d\+ Pro [^M])
PLATFORM_IOS = iOS Simulator,id=$(IOS_UDID)
XCODE_CONFIG = $(if $(filter release Release,$(CONFIG)),Release,$(if $(filter debug Debug,$(CONFIG)),Debug,$(error Unknown CONFIG '$(CONFIG)', expected debug or release)))


default: test-all

test-all: $(MAKE) CONFIG=debug test-library
	$(MAKE) CONFIG=release test-library

test-library:
	@if [ -z "$(IOS_RUNTIME_RESOLVED)" ]; then \
		echo "ERROR: no '$(IOS_RUNTIME)' runtime installed on this runner. Bump IOS_RUNTIME to an installed runtime:"; \
		xcrun simctl list runtimes available; \
		exit 1; \
	fi
	@if [ -z "$(IOS_UDID)" ]; then \
		echo "ERROR: no 'iPhone Pro' simulator for '$(IOS_RUNTIME_RESOLVED)' (family '$(IOS_RUNTIME)') on this runner. Bump IOS_RUNTIME to an installed runtime:"; \
		xcrun simctl list runtimes; \
		exit 1; \
	fi
	xcrun simctl bootstatus $(IOS_UDID) -b
	for platform in "$(PLATFORM_IOS)"; do \
		env TEST_RUNNER_GITHUB_CI=$(GITHUB_CI) \
		xcodebuild test \
			-resultBundlePath TestResults-$(XCODE)-$(CONFIG) \
			-enableCodeCoverage YES \
			-configuration $(XCODE_CONFIG) \
			$(if $(filter Release,$(XCODE_CONFIG)),ENABLE_TESTABILITY=YES) \
			'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$$(inherited) KLAVIYO_TESTING' \
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

# ---- Documentation (DocC) ----
# Base path the site is hosted under, e.g. DOCS_BASE_PATH=klaviyo-swift-sdk/5.6. Empty serves from "/".
DOCS_BASE_PATH ?=
DOCS_PORT ?= 8000
DOCS_SERVE_ROOT = build/docs/serve

.PHONY: docs docs-serve docs-preview

docs:
	scripts/build-docs.sh --hosting-base-path "$(DOCS_BASE_PATH)" $(if $(filter 1,$(DOCC_STRICT)),--strict)

# Serves the built site at http://localhost:$(DOCS_PORT)/<DOCS_BASE_PATH>/ so links resolve as they will
# on GitHub Pages. Mirrors the base path by symlinking the site into a scratch serve root.
docs-serve: docs
	@base="$(DOCS_BASE_PATH)"; base="$${base#/}"; base="$${base%/}"; \
	if [ -z "$$base" ]; then root="build/docs/site"; else \
		root="$(DOCS_SERVE_ROOT)"; rm -rf "$$root"; mkdir -p "$$root/$$(dirname "$$base")"; \
		ln -s "$(CURDIR)/build/docs/site" "$$root/$$base"; fi; \
	echo "Serving http://localhost:$(DOCS_PORT)/$${base:+$$base/}documentation/"; \
	cd "$$root" && python3 -m http.server $(DOCS_PORT)

# Local demo: builds the site for the root path and serves it at http://localhost:$(DOCS_PORT)/.
docs-preview:
	$(MAKE) docs-serve DOCS_BASE_PATH=
