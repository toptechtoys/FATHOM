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
    "Exit codes: 0 success, 2 invalid input, 3 missing prerequisite," \
    "            4 artifact exists, 5 notarization rejected."
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

# `notarytool submit --wait` returns once the service says Accepted, Invalid OR
# Rejected, and its man page documents no exit status for the last two, so the
# bare command cannot be trusted to fail. It also discards the submission ID,
# which is the only handle on the reason: with no ticket, the next line reports
# `Could not find base64 encoded ticket in response` / `Error 65` from stapler
# and names nothing actionable. Read the status back and print the log instead.
notarize() {
  local artifact="$1" result_plist submission status
  printf ' + xcrun notarytool submit %q --keychain-profile %q --wait\n' \
    "${artifact}" "${FATHOM_NOTARY_PROFILE}"
  [[ "${dry_run}" == false ]] || return 0
  result_plist="${temporary_directory}/notary-result.plist"
  xcrun notarytool submit "${artifact}" \
    --keychain-profile "${FATHOM_NOTARY_PROFILE}" \
    --output-format plist --wait >"${result_plist}" || true
  submission="$(/usr/libexec/PlistBuddy -c 'Print :id' "${result_plist}" 2>/dev/null || true)"
  status="$(/usr/libexec/PlistBuddy -c 'Print :status' "${result_plist}" 2>/dev/null || true)"
  printf 'release: notarization returned %s for %s (submission %s)\n' \
    "${status:-<none>}" "${artifact}" "${submission:-<none>}" >&2
  if [[ "${status}" != "Accepted" ]]; then
    if [[ -n "${submission}" ]]; then
      xcrun notarytool log "${submission}" \
        --keychain-profile "${FATHOM_NOTARY_PROFILE}" >&2 || true
    fi
    fail "notarization did not return Accepted for ${artifact}" 5
  fi
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "required command not found: ${command_name}" 3
}

# `codesign --verify --deep --strict` proves far less than it reads as. Measured
# on this machine: a bundle signed `codesign --sign -` passes it with "valid on
# disk / satisfies its Designated Requirement", exit 0. It cannot tell a
# Developer ID signature from an ad-hoc one, and it does not report the hardened
# runtime or the secure timestamp — both of which the notary service requires
# and neither of which this project has ever produced. Assert them positively,
# before spending ten minutes on a submission that would be rejected.
assert_developer_id() {
  local target="$1" description
  description="$(codesign --display --verbose=4 "${target}" 2>&1)" ||
    fail "codesign could not read a signature from ${target}" 3
  [[ "${description}" == *"Authority=Developer ID Application:"* ]] ||
    fail "${target} is not signed by a Developer ID Application certificate" 3
  [[ "${description}" != *adhoc* ]] ||
    fail "${target} carries an ad-hoc signature" 3
  [[ "${description}" == *"flags="*runtime* ]] ||
    fail "${target} was signed without the hardened runtime" 3
  [[ "${description}" == *"Timestamp="* ]] ||
    fail "${target} has no secure timestamp (codesign reports Signed Time= instead); the notary service will reject it" 3
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

# These two were written as `: "${VAR:?message}"`, which reads as a guard and is
# not one. The shell aborts the expansion with status 1, and the EXIT trap above
# resets it to 0 before the process leaves — measured on this machine's bash
# 3.2.57: with both variables unset, `scripts/release.sh --release-version
# 1.0.0 --dry-run` printed the message and exited 0, so a release run reported
# success having done nothing, and contradicted line 38 twice over. A
# status-preserving trap does not fix it either — `$?` is already 0 inside the
# trap when the shell aborts on the expansion — but an explicit `exit` from
# fail() does survive it, which is what these are.
[[ -n "${FATHOM_DEVELOPER_ID_APPLICATION:-}" ]] ||
  fail "set FATHOM_DEVELOPER_ID_APPLICATION to the exact Developer ID Application identity" 2
[[ -n "${FATHOM_NOTARY_PROFILE:-}" ]] ||
  fail "set FATHOM_NOTARY_PROFILE to the notarytool keychain profile name" 2
kernel_name="$(uname -s)"
[[ "${kernel_name}" == "Darwin" ]] || fail "release packaging requires macOS" 3

for prerequisite in xcodegen xcodebuild codesign xcrun ditto hdiutil spctl security; do
  require_command "${prerequisite}"
done

# notarytool and stapler live inside Xcode rather than on PATH, so the loop
# above cannot see them; ask xcrun, which is how the script invokes them.
xcrun --find notarytool >/dev/null 2>&1 ||
  fail "xcrun cannot find notarytool; install the full Xcode command line tools" 3
xcrun --find stapler >/dev/null 2>&1 ||
  fail "xcrun cannot find stapler; install the full Xcode command line tools" 3

# The identity and the notary profile are the two things this project has never
# had: today `security find-identity -v -p codesigning` prints "0 valid
# identities found" and notarytool answers "No Keychain password item found for
# profile: fathom-notary". Both probes cost under two seconds; without them the
# gap is discovered after xcodegen and a full Release archive. Compare against a
# captured variable rather than piping into `grep -qF`: `set -o pipefail` plus
# grep closing the pipe early makes that pipeline fail on SIGPIPE.
if [[ "${dry_run}" == false ]]; then
  codesigning_identities="$(security find-identity -v -p codesigning)"
  [[ "${codesigning_identities}" == *"${FATHOM_DEVELOPER_ID_APPLICATION}"* ]] ||
    fail "no codesigning identity matches ${FATHOM_DEVELOPER_ID_APPLICATION}; run: security find-identity -v -p codesigning" 3
  xcrun notarytool history --keychain-profile "${FATHOM_NOTARY_PROFILE}" >/dev/null 2>&1 ||
    fail "no notarytool keychain profile named ${FATHOM_NOTARY_PROFILE}; run: xcrun notarytool store-credentials ${FATHOM_NOTARY_PROFILE} --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID" 3
fi

# The app icons are Git LFS objects. An unresolved pointer still compiles, so a
# release could ship with 132 bytes of text where the icon belongs. Check every
# icon, not just one: a partially materialised checkout is exactly the case a
# single-file probe would wave through.
readonly icon_directory="${PROJECT_ROOT}/Fathom/Resources/Assets.xcassets/AppIcon.appiconset"
icons_checked=0
for icon_path in "${icon_directory}"/*.png; do
  [[ -f "${icon_path}" ]] || continue
  icons_checked=$((icons_checked + 1))
  icon_header="$(head -c 64 -- "${icon_path}")"
  case "${icon_header}" in
    *git-lfs.github.com*)
      fail "unresolved Git LFS pointer: ${icon_path}; run: git lfs checkout" 3
      ;;
    *)
      ;;
  esac
done
[[ "${icons_checked}" -gt 0 ]] || fail "no app icons found in ${icon_directory}" 3

readonly archive_path="${output_directory}/FATHOM-${release_version}.xcarchive"
readonly zip_path="${output_directory}/FATHOM-${release_version}.zip"
readonly dmg_path="${output_directory}/FATHOM-${release_version}.dmg"

for artifact in "${archive_path}" "${zip_path}" "${dmg_path}"; do
  [[ ! -e "${artifact}" ]] ||
    fail "refusing to overwrite ${artifact}; a failed run leaves the .xcarchive behind — remove ${output_directory}/FATHOM-${release_version}.* and rerun, or pick a new --release-version" 4
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
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  archive

run ditto "${archive_path}/Products/Applications/FATHOM.app" "${staged_app}"
run codesign --verify --deep --strict --verbose=2 "${staged_app}"

# --deep is not enough on its own, and the reason is this bundle's shape. With
# the menu bar helper nested somewhere codesign treats as data, --deep does not
# recurse into it: measured on a two-level bundle whose inner .app had its
# signature removed outright, `codesign --verify --deep --strict --verbose=4`
# still reported "valid on disk / satisfies its Designated Requirement" and
# exited 0. Walk the nested bundles by hand and assert each one, wherever the
# copy phase puts them.
if [[ "${dry_run}" == false ]]; then
  assert_developer_id "${staged_app}"
  nested_bundles="${temporary_directory}/nested-bundles.txt"
  # Redirect to a file rather than reading from a process substitution: under
  # .shellcheckrc's `enable=all` the latter is SC2312, and a failing find would
  # be silently read as "no nested code", which is the exact blind spot this
  # loop exists to close.
  find "${staged_app}" -name '*.app' >"${nested_bundles}"
  while IFS= read -r nested_bundle; do
    [[ "${nested_bundle}" != "${staged_app}" ]] || continue
    printf ' + verify nested %q\n' "${nested_bundle}"
    codesign --verify --strict --verbose=2 "${nested_bundle}" ||
      fail "nested bundle failed verification: ${nested_bundle}" 3
    assert_developer_id "${nested_bundle}"
  done <"${nested_bundles}"
fi

run ditto -c -k --keepParent "${staged_app}" "${submission_zip}"
notarize "${submission_zip}"
run xcrun stapler staple "${staged_app}"
run xcrun stapler validate "${staged_app}"
run spctl --assess --type execute --verbose=2 "${staged_app}"
run ditto -c -k --keepParent "${staged_app}" "${zip_path}"
run hdiutil create -volname FATHOM -srcfolder "${staged_app}" \
  -ov -format UDZO "${dmg_path}"

# The disk image was never signed, so the Gatekeeper assessment on the last line
# of this script could not pass — measured against an unsigned UDZO image built
# exactly this way: `spctl --assess --type open --context
# context:primary-signature` returns "rejected / source=no usable signature",
# exit 3, and it returns it after two full notarization round trips. --identifier
# is required because a disk image has no Info.plist for codesign to derive one
# from; it stays distinct from the app's com.exhibinaut.fathom.
run codesign --force --sign "${FATHOM_DEVELOPER_ID_APPLICATION}" \
  --timestamp --identifier com.exhibinaut.fathom.dmg "${dmg_path}"
run codesign --verify --strict --verbose=2 "${dmg_path}"
notarize "${dmg_path}"
run xcrun stapler staple "${dmg_path}"
run xcrun stapler validate "${dmg_path}"
run spctl --assess --type open --context context:primary-signature --verbose=2 "${dmg_path}"

printf 'release: created %s and %s\n' "${dmg_path}" "${zip_path}"
