#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci-common.sh
source "${SCRIPT_DIR}/ci-common.sh"

LOG_FILE="${LOG_DIR}/vreader-unsigned-ipa-$(now_utc).log"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"
SOURCE_PACKAGES_DIR="${BUILD_DIR}/SourcePackages"
IPA_WORK_DIR="${BUILD_DIR}/unsigned-ipa"
PAYLOAD_DIR="${IPA_WORK_DIR}/Payload"
IPA_PATH="${ARTIFACT_DIR}/vreader-unsigned.ipa"
PROJECT_PATH="${ROOT_DIR}/vreader.xcodeproj"
SCHEME="${SCHEME:-vreader}"
CONFIGURATION="${CONFIGURATION:-Release}"

# VReader's project.yml currently opts into Swift 6 + complete strict concurrency.
# That is useful for app development, but the public fork currently fails under
# Xcode 16.4 before we can produce a preview IPA because of existing actor/
# Sendable diagnostics. For this preview artifact only, default to Swift 5
# compatibility and minimal concurrency checking. Override these env vars if
# you want to test the stricter upstream configuration.
VREADER_SWIFT_VERSION="${VREADER_SWIFT_VERSION:-5.0}"
VREADER_SWIFT_STRICT_CONCURRENCY="${VREADER_SWIFT_STRICT_CONCURRENCY:-minimal}"

on_error() {
  local status=$?
  print_error_summary "${LOG_FILE}" "${status}"
  exit "${status}"
}
trap on_error ERR

section "Environment" | tee "${LOG_FILE}"
{
  echo "Root: ${ROOT_DIR}"
  echo "Scheme: ${SCHEME}"
  echo "Configuration: ${CONFIGURATION}"
  echo "Swift version override: ${VREADER_SWIFT_VERSION}"
  echo "Strict concurrency override: ${VREADER_SWIFT_STRICT_CONCURRENCY}"
  echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "Swift: $(xcrun swift --version | head -n 1)"
} | tee -a "${LOG_FILE}"

require_command xcodegen
require_command xcodebuild
require_command xcrun
require_command zip

section "Generate Xcode project" | tee -a "${LOG_FILE}"
run_logged "${LOG_FILE}" xcodegen generate --spec "${ROOT_DIR}/project.yml"

if [ ! -d "${PROJECT_PATH}" ]; then
  fail "Generated project not found: ${PROJECT_PATH}"
fi

section "Resolve Swift packages" | tee -a "${LOG_FILE}"
run_logged "${LOG_FILE}" xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_DIR}" \
  -resolvePackageDependencies

section "Build unsigned iOS app" | tee -a "${LOG_FILE}"
run_logged "${LOG_FILE}" xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_DIR}" \
  SWIFT_VERSION="${VREADER_SWIFT_VERSION}" \
  SWIFT_STRICT_CONCURRENCY="${VREADER_SWIFT_STRICT_CONCURRENCY}" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

APP_PATH="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}-iphoneos/vreader.app"
if [ ! -d "${APP_PATH}" ]; then
  echo "Expected app path not found: ${APP_PATH}" >>"${LOG_FILE}"
  find "${DERIVED_DATA_DIR}/Build/Products" -maxdepth 3 -name "*.app" -print >>"${LOG_FILE}" 2>/dev/null || true
  fail "Could not find built vreader.app"
fi

section "Package unsigned IPA" | tee -a "${LOG_FILE}"
rm -rf "${IPA_WORK_DIR}" "${IPA_PATH}"
mkdir -p "${PAYLOAD_DIR}"
cp -R "${APP_PATH}" "${PAYLOAD_DIR}/"
(
  cd "${IPA_WORK_DIR}"
  zip -qry "${IPA_PATH}" Payload
)

if [ ! -f "${IPA_PATH}" ]; then
  fail "IPA was not created: ${IPA_PATH}"
fi

section "Done" | tee -a "${LOG_FILE}"
{
  echo "IPA: ${IPA_PATH}"
  echo "Log: ${LOG_FILE}"
  ls -lh "${IPA_PATH}"
} | tee -a "${LOG_FILE}"
