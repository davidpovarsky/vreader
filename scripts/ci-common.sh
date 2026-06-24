#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
LOG_DIR="${BUILD_DIR}/logs"
ARTIFACT_DIR="${BUILD_DIR}/artifacts"
mkdir -p "${LOG_DIR}" "${ARTIFACT_DIR}"

now_utc() {
  date -u +"%Y%m%d-%H%M%S"
}

section() {
  echo ""
  echo "================ $* ================"
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Required command not found: $1"
  fi
}

print_error_summary() {
  local log_file="$1"
  local exit_code="${2:-1}"

  echo ""
  echo "================ COPY THIS ERROR SUMMARY ================"
  echo "Exit code: ${exit_code}"
  echo "Log file: ${log_file}"
  echo ""

  if [ ! -f "${log_file}" ]; then
    echo "Log file was not created."
    echo "================ END COPY THIS ERROR SUMMARY ============="
    return 0
  fi

  echo "Actual error lines only, capped at 60:"
  python3 - "${log_file}" <<'PY'
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
patterns = [
    re.compile(r"\berror:\s", re.IGNORECASE),
    re.compile(r"\bfatal error:\s", re.IGNORECASE),
    re.compile(r"xcodebuild: error", re.IGNORECASE),
    re.compile(r"Command PhaseScriptExecution failed", re.IGNORECASE),
    re.compile(r"Package resolution failed", re.IGNORECASE),
    re.compile(r"Signing for .* requires a development team", re.IGNORECASE),
    re.compile(r"No profiles for .* were found", re.IGNORECASE),
    re.compile(r"Provisioning profile", re.IGNORECASE),
    re.compile(r"CodeSign error", re.IGNORECASE),
]

skip_fragments = (
    "SwiftCompile normal",
    "CompileSwift normal",
    "Ld ",
    "PhaseScriptExecution ",
    "Command line invocation:",
    "Build settings from command line:",
)

seen = set()
errors = []
for lineno, line in enumerate(log_path.read_text(errors="replace").splitlines(), 1):
    stripped = line.strip()
    if not stripped:
        continue
    if any(fragment in stripped for fragment in skip_fragments) and "error:" not in stripped.lower():
        continue
    if any(pattern.search(stripped) for pattern in patterns):
        # Shorten huge xcodebuild/swift lines while preserving the actual error.
        compact = re.sub(r"\s+", " ", stripped)
        if len(compact) > 700:
            compact = compact[:700] + " ... [truncated]"
        key = compact
        if key not in seen:
            seen.add(key)
            errors.append(f"{lineno}: {compact}")

if not errors:
    print("No explicit error lines found. Open the uploaded .log artifact for the full build log.")
else:
    for item in errors[:60]:
        print(item)
    if len(errors) > 60:
        print(f"... {len(errors) - 60} more error line(s) omitted. Open the .log artifact for the full log.")
PY

  echo ""
  echo "Full log is uploaded as a workflow artifact; do not paste it unless asked."
  echo "================ END COPY THIS ERROR SUMMARY ============="
}

run_logged() {
  local log_file="$1"
  shift
  section "Running: $*" | tee -a "${log_file}"
  set +e
  "$@" >>"${log_file}" 2>&1
  local status=$?
  set -e
  if [ "${status}" -ne 0 ]; then
    print_error_summary "${log_file}" "${status}"
    exit "${status}"
  fi
}
