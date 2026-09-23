#!/usr/bin/env bash
# Feature #177 WI-1 RED gate: pin the platform, CI runner, and package baselines
# before any AI-agent production code is allowed to compile against them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/project.yml"
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
assert_contains "$WORKFLOW" 'Run Feature 177 core contract tests'
assert_contains "$WORKFLOW" 'vreaderTests/AIDocumentModelsTests'
assert_contains "$WORKFLOW" 'vreaderTests/AIReadingBoundaryPolicyTests'
assert_contains "$TEST_RUNNER" 'ACTIVE_DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"'
assert_contains "$TEST_RUNNER" '-skipPackagePluginValidation'
assert_contains "$TEST_RUNNER" '-skipMacroValidation'

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

echo "ios27-ai-agent-baseline: PASS"
