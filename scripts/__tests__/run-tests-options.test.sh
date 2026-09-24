#!/usr/bin/env bash
# Contract for the environment-controlled xcodebuild options used by focused CI.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$HERE/../run-tests.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cat > "$TMP/bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CAPTURE_ARGS"
echo "** TEST EXECUTE SUCCEEDED **"
EOF
chmod +x "$TMP/bin/xcodebuild"

run_fake() {
    env PATH="$TMP/bin:$PATH" \
        DEVELOPER_DIR=/fake/Xcode.app/Contents/Developer \
        TEST_UDID=FAKE-UDID-0000 \
        TEST_LOG_PATH="$TMP/xcodebuild.log" \
        CAPTURE_ARGS="$1" \
        "${@:2}" \
        bash "$RUN" Feature177CoreTests >/dev/null
}

assert_arg_pair() {
    local file="$1" first="$2" second="$3"
    if ! awk -v first="$first" -v second="$second" '
        previous == first && $0 == second { found = 1 }
        { previous = $0 }
        END { exit found ? 0 : 1 }
    ' "$file"; then
        echo "missing argument pair: $first $second" >&2
        exit 1
    fi
}

run_fake "$TMP/default.args"
assert_arg_pair "$TMP/default.args" -scheme vreader
assert_arg_pair "$TMP/default.args" -collect-test-diagnostics never

run_fake "$TMP/focused.args" \
    TEST_SCHEME=Feature177Core \
    TEST_COLLECT_DIAGNOSTICS=always \
    TEST_DERIVED_DATA_PATH="$TMP/DerivedData" \
    TEST_RESULT_BUNDLE_PATH="$TMP/result/Feature177.xcresult"
assert_arg_pair "$TMP/focused.args" -scheme Feature177Core
assert_arg_pair "$TMP/focused.args" -collect-test-diagnostics always
assert_arg_pair "$TMP/focused.args" -derivedDataPath "$TMP/DerivedData"
assert_arg_pair "$TMP/focused.args" -resultBundlePath "$TMP/result/Feature177.xcresult"

echo "run-tests-options: PASS"
