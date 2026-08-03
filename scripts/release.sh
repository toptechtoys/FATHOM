#!/usr/bin/env bash
# Build, Developer ID sign, notarize, staple, and package FATHOM.
# Requires macOS, Xcode 26, XcodeGen, and Bash 3.2 or later.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly PROJECT_ROOT

release_version=""
output_directory="${PROJECT_ROOT}/dist"
dry_run=false
temporary_directory=""

usage() {
  printf '%s\n' \
    "Usage: scripts/release.sh --release-version X.Y.Z [options]" \
    "" \
    "Options:" \
    "  --release-version VERSION  Required numeric release version." \
    "  --output DIRECTORY          Artifact directory (default: dist)." \
    "  --dry-run                   Print commands without executing them." \
    "  --help, -h                  Show this help." \
    "  --version                   Show script version." \
    "" \
    "Required environment:" \
    "  FATHOM_DEVELOPER_ID_APPLICATION  Exact Developer ID identity." \
    "  FATHOM_NOTARY_PROFILE            notarytool keychain profile." \
    "" \
    "Outputs:" \
    "  FATHOM-VERSION.dmg and FATHOM-VERSION.zip" \
    "" \
    "Exit codes: 0 success, 2 invalid input, 3 missing prerequisite, 4 artifact exists."
}

fail() {
  local message="$1"
  local code="${2:-1}"
  printf 'release: %s\n' "${message}" >&2
  exit "${code}"
}

cleanup() {
  if [[ -n "${temporary_directory}" && -d "${temporary_directory}" ]]; then
    rm -rf -- "${temporary_directory}"
  fi
}
trap cleanup EXIT
trap 'fail "failed at line ${LINENO}" 1' ERR

run() {
  printf ' +'
  printf ' %q' "$@"
  printf '\n'
  if [[ "${dry_run}" == false ]]; then
    "$@"
  fi
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "required command not found: ${command_name}" 3
}

while (($# > 0)); do
  case "$1" in
    --release-version)
      (($# >= 2)) || fail "--release-version requires a value" 2
      release_version="$2"
      shift 2
      ;;
    --output)
      (($# >= 2)) || fail "--output requires a value" 2
      output_directory="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --version)
      printf '%s\n' "${SCRIPT_VERSION}"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      fail "unknown option: $1" 2
      ;;
  esac
done

[[ $# -eq 0 ]] || fail "unexpected positional arguments" 2
[[ "${release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fail "release version must match X.Y.Z" 2
: "${FATHOM_DEVELOPER_ID_APPLICATION:?set the exact Developer ID Application identity}"
: "${FATHOM_NOTARY_PROFILE:?set the notarytool keychain profile name}"
kernel_name="$(uname -s)"
[[ "${kernel_name}" == "Darwin" ]] || fail "release packaging requires macOS" 3

for prerequisite in xcodegen xcodebuild codesign xcrun ditto hdiutil spctl; do
  require_command "${prerequisite}"
done

readonly archive_path="${output_directory}/FATHOM-${release_version}.xcarchive"
readonly zip_path="${output_directory}/FATHOM-${release_version}.zip"
readonly dmg_path="${output_directory}/FATHOM-${release_version}.dmg"

for artifact in "${archive_path}" "${zip_path}" "${dmg_path}"; do
  [[ ! -e "${artifact}" ]] || fail "refusing to overwrite ${artifact}" 4
done

run mkdir -p -- "${output_directory}"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fathom-release.XXXXXX")"
readonly staged_app="${temporary_directory}/FATHOM.app"
readonly submission_zip="${temporary_directory}/FATHOM-notary.zip"

run xcodegen generate --spec "${PROJECT_ROOT}/project.yml"
run xcodebuild \
  -project "${PROJECT_ROOT}/Fathom.xcodeproj" \
  -scheme Fathom \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "${archive_path}" \
  MARKETING_VERSION="${release_version}" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  CODE_SIGN_IDENTITY="${FATHOM_DEVELOPER_ID_APPLICATION}" \
  archive

run ditto "${archive_path}/Products/Applications/FATHOM.app" "${staged_app}"
run codesign --verify --deep --strict --verbose=2 "${staged_app}"
run ditto -c -k --keepParent "${staged_app}" "${submission_zip}"
run xcrun notarytool submit "${submission_zip}" \
  --keychain-profile "${FATHOM_NOTARY_PROFILE}" --wait
run xcrun stapler staple "${staged_app}"
run xcrun stapler validate "${staged_app}"
run spctl --assess --type execute --verbose=2 "${staged_app}"
run ditto -c -k --keepParent "${staged_app}" "${zip_path}"
run hdiutil create -volname FATHOM -srcfolder "${staged_app}" \
  -ov -format UDZO "${dmg_path}"
run xcrun notarytool submit "${dmg_path}" \
  --keychain-profile "${FATHOM_NOTARY_PROFILE}" --wait
run xcrun stapler staple "${dmg_path}"
run xcrun stapler validate "${dmg_path}"
run spctl --assess --type open --context context:primary-signature --verbose=2 "${dmg_path}"

printf 'release: created %s and %s\n' "${dmg_path}" "${zip_path}"
