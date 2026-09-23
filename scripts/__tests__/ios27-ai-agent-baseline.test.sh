#!/usr/bin/env bash
# Feature #177 WI-1 RED gate: pin the platform, CI runner, and package baselines
# before any AI-agent production code is allowed to compile against them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/project.yml"
WORKFLOW="$ROOT/.github/workflows/build-unsigned-ipa.yml"

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
