#!/usr/bin/env bash
# Feature #177 WI-1 RED gate: pin the platform, CI runner, and package baselines
# before any AI-agent production code is allowed to compile against them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/project.yml"
FOCUSED_PROJECT="$ROOT/Feature177Core.project.yml"
MAPPING_PROJECT="$ROOT/Feature177Mapping.project.yml"
WORKFLOW="$ROOT/.github/workflows/build-unsigned-ipa.yml"
TEST_RUNNER="$ROOT/scripts/run-tests.sh"

assert_contains() {
    local file="$1"
    local needle="$2"
    if ! grep -Fq -- "$needle" "$file"; then
        echo "expected '$needle' in ${file#$ROOT/}" >&2
        exit 1
    fi
}

assert_contains "$PROJECT" 'iOS: "27.0"'
assert_contains "$PROJECT" 'xcodeVersion: "27.0"'
assert_contains "$PROJECT" 'exactVersion: "3.11.0"'
assert_contains "$PROJECT" 'exactVersion: "0.12.1"'
assert_contains "$PROJECT" 'exactVersion: "3.31.4"'
assert_contains "$PROJECT" 'exactVersion: "0.11.0"'
assert_contains "$PROJECT" 'exactVersion: "2.26.2"'

assert_contains "$WORKFLOW" 'runs-on: xcode-27'
assert_contains "$WORKFLOW" 'Select Xcode 27'
assert_contains "$WORKFLOW" '27.*) ;;'
assert_contains "$WORKFLOW" 'Build unsigned app against iOS 27 SDK'
assert_contains "$WORKFLOW" '-skipPackagePluginValidation'
assert_contains "$WORKFLOW" '-skipMacroValidation'
assert_contains "$WORKFLOW" 'xcodebuild -downloadComponent MetalToolchain'
assert_contains "$WORKFLOW" 'run_feature_177_core_tests:'
assert_contains "$WORKFLOW" 'run_feature_177_mapping_tests:'
assert_contains "$WORKFLOW" 'Run Feature 177 core contract tests'
assert_contains "$WORKFLOW" '-scheme Feature177Core'
assert_contains "$WORKFLOW" 'Feature177CoreTests'
assert_contains "$WORKFLOW" 'TEST_CONFIGURATION: Release'
assert_contains "$WORKFLOW" 'TEST_ONLY_ACTIVE_ARCH: YES'
assert_contains "$WORKFLOW" 'TEST_XCODEBUILD_ACTION: test-without-building'
assert_contains "$WORKFLOW" 'TEST_SCHEME: Feature177Core'
assert_contains "$WORKFLOW" 'TEST_COLLECT_DIAGNOSTICS: never'
assert_contains "$WORKFLOW" 'TIMEOUT_SECS: 300'
assert_contains "$WORKFLOW" 'feature-177-core-tests'
assert_contains "$WORKFLOW" 'Run Feature 177 mapping tests'
assert_contains "$WORKFLOW" 'Feature177MappingTests'
assert_contains "$WORKFLOW" 'TEST_SCHEME: Feature177Mapping'
assert_contains "$WORKFLOW" 'feature-177-mapping-tests'
assert_contains "$WORKFLOW" '-destination "platform=iOS Simulator,id=${FEATURE_TEST_UDID}"'
assert_contains "$FOCUSED_PROJECT" 'Feature177CoreTests:'
assert_contains "$FOCUSED_PROJECT" 'FEATURE_177_CORE_TESTS'
assert_contains "$FOCUSED_PROJECT" 'Feature177Core:'
assert_contains "$MAPPING_PROJECT" 'Feature177MappingTests:'
assert_contains "$MAPPING_PROJECT" 'Feature177Mapping:'
assert_contains "$WORKFLOW" '--spec Feature177Core.project.yml'
assert_contains "$WORKFLOW" 'build/Feature177Project/Feature177Core.xcodeproj'
assert_contains "$TEST_RUNNER" 'ACTIVE_DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"'
assert_contains "$TEST_RUNNER" 'CONFIGURATION="${TEST_CONFIGURATION:-Debug}"'
assert_contains "$TEST_RUNNER" 'SCHEME="${TEST_SCHEME:-vreader}"'
assert_contains "$TEST_RUNNER" 'COLLECT_DIAGNOSTICS="${TEST_COLLECT_DIAGNOSTICS:-never}"'
assert_contains "$TEST_RUNNER" 'ONLY_ACTIVE_ARCH="${TEST_ONLY_ACTIVE_ARCH:-NO}"'
assert_contains "$TEST_RUNNER" 'BUILD_SETTING_ARGS+=("ONLY_ACTIVE_ARCH=$ONLY_ACTIVE_ARCH")'
assert_contains "$TEST_RUNNER" 'XCODEBUILD_ACTION="${TEST_XCODEBUILD_ACTION:-test}"'
assert_contains "$TEST_RUNNER" 'xcodebuild "$XCODEBUILD_ACTION"'
assert_contains "$TEST_RUNNER" '-configuration "$CONFIGURATION"'
assert_contains "$TEST_RUNNER" '-skipPackagePluginValidation'
assert_contains "$TEST_RUNNER" '-skipMacroValidation'
assert_contains "$TEST_RUNNER" '-collect-test-diagnostics "$COLLECT_DIAGNOSTICS"'
assert_contains "$TEST_RUNNER" "TEST( EXECUTE)? SUCCEEDED"

# USearch 2.26.2 resolves NumKong 7.8.2, whose header-only CNumKong target
# triggers swift-package-manager#5706 in Xcode's transitive linker. Pin the
# audited one-source fork at an immutable commit until upstream ships the fix.
assert_contains "$PROJECT" 'url: https://github.com/davidpovarsky/NumKong'
assert_contains "$PROJECT" 'revision: "cb62f80c80e1a9357eda94e98c03db91a3e5e037"'

if grep -Fq 'Generate CNumKong linker shim' "$PROJECT"; then
    echo "target-level CNumKong shim reintroduces a Debug package cycle" >&2
    exit 1
fi

if grep -Fq 'runs-on: macos-26' "$WORKFLOW"; then
    echo "workflow still targets macos-26" >&2
    exit 1
fi

if grep -Fq 'SWIFT_VERSION=5.0' "$WORKFLOW"; then
    echo "workflow must not force Swift 5 onto Swift 6 package dependencies" >&2
    exit 1
fi

if grep -Fq 'SWIFT_STRICT_CONCURRENCY=minimal' "$WORKFLOW"; then
    echo "workflow must not weaken the project's complete-concurrency setting" >&2
    exit 1
fi

if ! grep -A4 'Install Metal Toolchain for MLX' "$WORKFLOW" | grep -Fq "if: \${{ github.event_name != 'workflow_dispatch' || (!inputs.run_feature_177_core_tests && !inputs.run_feature_177_mapping_tests) }}"; then
    echo "Metal toolchain installation must be gated off for the focused lane" >&2
    exit 1
fi

FEATURE_TARGET="$(sed -n '/^  Feature177CoreTests:/,/^schemes:/p' "$FOCUSED_PROJECT")"
if grep -Eq 'target: vreader|package:' <<<"$FEATURE_TARGET"; then
    echo "Feature177CoreTests must not depend on the app or external packages" >&2
    exit 1
fi

if grep -Fq 'actions/cache@v4' "$WORKFLOW"; then
    echo "the lightweight Feature 177 lane must not restore the old Xcode cache" >&2
    exit 1
fi

if grep -Fq 'packages:' "$FOCUSED_PROJECT"; then
    echo "standalone Feature 177 project must not declare a package graph" >&2
    exit 1
fi

if grep -Fq 'packages:' "$MAPPING_PROJECT"; then
    echo "standalone Feature 177 mapping project must not declare a package graph" >&2
    exit 1
fi

FOCUSED_COMPILE="$(sed -n '/Compile Feature 177 contracts/,/Run Feature 177 core contract tests/p' "$WORKFLOW")"
if grep -Eq -- '-scheme vreader|vreaderUITests|build/vreader-original-ui-ios27-unsigned\.ipa' <<<"$FOCUSED_COMPILE"; then
    echo "focused compile path leaked the app/UI-test/IPA graph" >&2
    exit 1
fi

echo "ios27-ai-agent-baseline: PASS"
