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
  if [ -f "${log_file}" ]; then
    echo "Likely error lines:"
    grep -nE "(^|[^A-Za-z])(error:|fatal error:|xcodebuild: error|Command PhaseScriptExecution failed|CodeSign|Provisioning profile|Signing for|No profiles|SwiftCompile|CompileSwift|Ld |PhaseScriptExecution|Package resolution failed)" "${log_file}" | tail -n 80 || true
    echo ""
    echo "Last 120 log lines:"
    tail -n 120 "${log_file}" || true
  else
    echo "Log file was not created."
  fi
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
