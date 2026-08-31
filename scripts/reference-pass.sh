#!/usr/bin/env bash
# Run the mechanical half of the reference-machine pass and fill a copy of
# docs/REFERENCE-PASS.md. Requires macOS, Xcode 26, XcodeGen, git-lfs, Bash 3.2.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly PROJECT_ROOT
readonly FORM="${PROJECT_ROOT}/docs/REFERENCE-PASS.md"

output_directory=""
volume="/"
signed_app=""
bar_wait=180
skip_benchmark=false
allow_non_apple_silicon=false
dry_run=false
silicon_warning=false
sampler_pid=""
blocking=()

usage() {
  printf '%s\n' \
    "Usage: scripts/reference-pass.sh [options]" \
    "" \
    "Runs everything the reference-machine session can capture without a" \
    "person, in the order that survives a failure: gate 2's one-shot raw" \
    "hardware capture first, then gate 1's benchmark, then gate 3's widget" \
    "cost, then what gates 4 to 6 and Distribution can prove mechanically." \
    "Results are written into a filled copy of docs/REFERENCE-PASS.md." \
    "" \
    "Options:" \
    "  --output DIRECTORY          Where the record and evidence go." \
    "                              Default: reference-pass/<UTC stamp>-<commit>." \
    "  --volume PATH               Volume for gate 1 (default: /)." \
    "  --signed-app PATH           The signed, hardened, notarized FATHOM.app." \
    "                              Gate 5 is only filled from this build." \
    "  --bar-wait SECONDS          How long to wait for the widget's own CPU" \
    "                              figure (default: 180)." \
    "  --skip-benchmark            Skip gate 1. Gate 2 still runs." \
    "  --allow-non-apple-silicon   Record the pass on an Intel Mac anyway," \
    "                              banner-stamped as a measurement of" \
    "                              something else. Never bypasses Rosetta." \
    "  --print-row-keys            Print the docs/REFERENCE-PASS.md row keys" \
    "                              this script fills, one per line, and exit." \
    "  --dry-run                   Print the ordered plan and touch nothing." \
    "  --help, -h                  Show this help." \
    "  --version                   Show script version." \
    "" \
    "Exit codes: 0 success, 2 invalid input, 3 missing prerequisite," \
    "            4 output exists, 5 a gate failed, 6 not Apple silicon." \
    "" \
    "A reading this Mac does not publish is an outcome, not a failure: it is" \
    "recorded verbatim and does not change the exit code. \`fathom" \
    "capture-fixtures\` follows the same rule and exits 0 with its gaps named" \
    "in capture-manifest.json."
}

fail() {
  local message="$1"
  local code="${2:-1}"
  printf 'reference-pass: %s\n' "${message}" >&2
  exit "${code}"
}

# Kills only the index-size sampler this script started, by the PID it recorded.
# Nothing here ever touches a running FATHOM.
cleanup() {
  if [[ -n "${sampler_pid}" ]]; then
    kill "${sampler_pid}" 2>/dev/null || true
    sampler_pid=""
  fi
}
trap cleanup EXIT
trap 'fail "failed at line ${LINENO}" 1' ERR

# Unlike scripts/release.sh's, this wrapper always executes: --dry-run here
# prints the plan and returns before any work starts, so a no-op branch would be
# dead code pretending to be a safety net.
run() {
  printf ' +'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "required command not found: ${command_name}" 3
}

# The leading cells of every docs/REFERENCE-PASS.md row this script fills.
#
# The filler matches these literally, so the likeliest long-term failure is
# somebody rewording a row: the match stops, the cell comes back empty, and an
# empty cell in that form means *not measured* — the record would quietly
# understate itself. tests/reference-pass.bats asserts every key below still
# appears in the form, which is what keeps the coupling honest.
row_keys() {
  printf '%s\n' \
    '| **Machine** |' \
    '| **macOS build** |' \
    '| **Volume, capacity, filesystem** |' \
    '| **Drive model and node** |' \
    '| **Date of pass** |' \
    '| **Commit under test** |' \
    '| **git-lfs objects present** |' \
    '| Scan rate | at least 18,000 entries/s; under 12,000 blocks |' \
    '| Files changed during the scan | recorded, never budgeted |' \
    '| Peak resident memory | under 300 MB |' \
    '| Peak index size on disk | no budget; **record it** |' \
    '| Free space before the run | — |' \
    '| NVMe SMART | Percentage used |' \
    '| NVMe SMART | Data written |' \
    '| NVMe SMART | Power-on hours |' \
    '| NVMe SMART | Unsafe shutdowns |' \
    "| SMC | Total system power (\`PSTR\`) |" \
    '| SMC | Fan keys |' \
    '| IOHID | Temperature sensor count |' \
    '| IOReport | Power channels published |' \
    '| NVMe SMART log page, raw bytes |' \
    '| SMC key inventory |' \
    '| SMC key values read |' \
    '| IOReport channel subscription |' \
    '| Widget CPU | ≤ 0.2% | 0.5% |' \
    '| Energy Impact | ≤ 2.1 | 4.0 |' \
    '| Onboarding |' \
    '| Menu-bar visibility guidance |' \
    '| Sleep/wake suspension |' \
    '| Memory-pressure second row |' \
    '| VoiceOver, per view |' \
    '| Keyboard navigation and focus ring |' \
    '| Dynamic Type to Accessibility Large |' \
    '| Reduce Motion |' \
    '| The plate reads correctly on a real display |' \
    '| Consent prompt appears |' \
    '| App survives the prompt |' \
    '| Paired devices publish after granting |' \
    '| Cold Bluetooth read, ms (first read only) |' \
    '| If denied: the exact denial observed |' \
    '| Every section keeps updating after a switch |' \
    '| Bluetooth populates on entry, no *not published* flash |' \
    '| Leaving Bluetooth stops the reads |' \
    "| \`security find-identity -v -p codesigning\` |" \
    "| \`notarytool\` profile configured |" \
    '| Signed, stapled app |' \
    '| Signed, stapled DMG |' \
    '| Gatekeeper assessment |' \
    '| **All gates recorded** |' \
    '| **Blocking failures** |' \
    '| **Issues opened** |' \
    '| **Cleared for release** |'
}

while (($# > 0)); do
  case "$1" in
    --output)
      (($# >= 2)) || fail "--output requires a value" 2
      output_directory="$2"
      shift 2
      ;;
    --volume)
      (($# >= 2)) || fail "--volume requires a value" 2
      volume="$2"
      shift 2
      ;;
    --signed-app)
      (($# >= 2)) || fail "--signed-app requires a value" 2
      signed_app="$2"
      shift 2
      ;;
    --bar-wait)
      (($# >= 2)) || fail "--bar-wait requires a value" 2
      bar_wait="$2"
      shift 2
      ;;
    --skip-benchmark)
      skip_benchmark=true
      shift
      ;;
    --allow-non-apple-silicon)
      allow_non_apple_silicon=true
      shift
      ;;
    --print-row-keys)
      row_keys
      exit 0
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
[[ "${bar_wait}" =~ ^[0-9]+$ ]] || fail "--bar-wait must be a whole number of seconds" 2
[[ -d "${volume}" ]] || fail "--volume is not a directory: ${volume}" 2
[[ -z "${signed_app}" || -d "${signed_app}" ]] ||
  fail "--signed-app is not a bundle: ${signed_app}" 2
[[ -f "${FORM}" ]] || fail "the blank form is missing: ${FORM}" 3

kernel_name="$(uname -s)"
[[ "${kernel_name}" == "Darwin" ]] || fail "the reference pass requires macOS" 3

# Every `|| printf` fallback below is load-bearing rather than defensive. On an
# Intel Mac both hw.optional.arm64 and sysctl.proc_translated are unknown OIDs,
# sysctl exits non-zero, and under `set -e` the bare call would abort the script
# at the exact check that exists to detect an Intel Mac.
architecture="$(uname -m)"
hardware_model="$(sysctl -n hw.model 2>/dev/null || printf 'not published')"
chip_brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || printf 'not published')"
arm64_optional="$(sysctl -n hw.optional.arm64 2>/dev/null || printf '0')"
translated="$(sysctl -n sysctl.proc_translated 2>/dev/null || printf '0')"

# Refused unconditionally, and --allow-non-apple-silicon does not reach it: a
# translated shell reports x86_64 whatever the silicon is, and every figure a
# translated `fathom` produces is a measurement of Rosetta.
[[ "${translated}" != "1" ]] ||
  fail "this shell is running under Rosetta; every figure it takes would measure Rosetta rather than the Mac" 6

if [[ "${architecture}" != "arm64" || "${arm64_optional}" != "1" ]]; then
  if [[ "${allow_non_apple_silicon}" == false ]]; then
    fail "this is not an Apple silicon Mac (${architecture}, ${hardware_model}); a number taken on an Intel Mac is a measurement of something else. Pass --allow-non-apple-silicon to record the run anyway." 6
  fi
  silicon_warning=true
fi

# A banner printed once into a terminal that then scrolls for twenty minutes is
# a banner nobody sees. This string is stamped into identity.txt, into every
# per-gate directory and at the top of the generated record.
silicon_banner=""
if [[ "${silicon_warning}" == true ]]; then
  silicon_banner="$(printf '%s\n' \
    '**********************************************************************' \
    '* NOT APPLE SILICON. Host: '"${architecture}"' / '"${hardware_model}" \
    '* Every Apple-silicon reading renders not published here: IOReport,' \
    '* SMC temperature, perflevel1, the NVMe SMART user client.' \
    '* A number taken on an Intel Mac is a measurement of something else.' \
    '**********************************************************************')"
  printf '%s\n' "${silicon_banner}" >&2
fi

commit="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null || printf 'not-a-git-checkout')"
short_commit="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -z "${output_directory}" ]]; then
  output_directory="${PROJECT_ROOT}/reference-pass/${stamp}-${short_commit}"
fi

# Checked before --dry-run returns, not after: a dry run that reports the plan
# is fine and then dies on its first mkdir has told the operator nothing, and
# the operator is at this machine once.
[[ ! -e "${output_directory}" ]] ||
  fail "refusing to overwrite ${output_directory}; pick a new --output or move the old pass aside" 4

if [[ "${dry_run}" == true ]]; then
  printf '%s\n' \
    "reference-pass: plan only; nothing is created and nothing is measured." \
    "  output:  ${output_directory}" \
    "  volume:  ${volume}" \
    "  host:    ${architecture} / ${hardware_model} / ${chip_brand}" \
    "  commit:  ${commit}" \
    "" \
    " 1. record machine identity, git-lfs objects and app-icon pointers" \
    " 2. swift build -c release --product fathom, then swift test" \
    " 3. fathom doctor — refuse to continue without Full Disk Access" \
    " 4. GATE 2 FIRST: fathom capture-fixtures (the one-shot raw payloads)" \
    " 5. gate 2 comparison rows out of fathom doctor" \
    " 6. GATE 1: fathom benchmark ${volume} --enforce-reference-gates," \
    "    with a background sampler for peak index size on disk" \
    " 7. GATE 3: build FathomBar, read its published idle CPU from defaults" \
    " 8. gates 5 and Distribution: codesign, spctl, find-identity, notarytool" \
    " 9. print the numbered checklist for every row a person must judge" \
    "10. write the filled copy of docs/REFERENCE-PASS.md"
  exit 0
fi

for prerequisite in git swift xcodebuild xcodegen sysctl sw_vers defaults \
  plutil shasum diskutil open codesign spctl security awk sed stat df python3; do
  require_command "${prerequisite}"
done
git lfs version >/dev/null 2>&1 ||
  fail "git-lfs is a build requirement, not a convenience; the app icons are LFS objects" 3

out="${output_directory}"
run mkdir -p -- "${out}/logs" "${out}/fixtures" "${out}/gate1" "${out}/gate3" \
  "${out}/gate5" "${out}/gate6" "${out}/distribution"
fills_file="${out}/logs/row-fills.tsv"
: >"${fills_file}"

add_fill() {
  local key="$1"
  shift
  local row="${key}" cell
  for cell in "$@"; do
    # A pipe inside a cell would silently invent a column; a newline would
    # invent a row. Neither can be allowed to reshape the record.
    cell="${cell//|/·}"
    cell="${cell//$'\n'/ }"
    row="${row} ${cell} |"
  done
  printf '%s\t%s\n' "${key}" "${row}" >>"${fills_file}"
}

readonly OPERATOR='_not measured — operator_'

# ---------------------------------------------------------------- identity ---

product_version="$(sw_vers -productVersion)"
build_version="$(sw_vers -buildVersion)"
memory_bytes="$(sysctl -n hw.memsize 2>/dev/null || printf 'not published')"
logical_cpus="$(sysctl -n hw.ncpu 2>/dev/null || printf 'not published')"
performance_cpus="$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || printf 'not published')"
efficiency_cpus="$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || printf 'not published')"
dirty_tree="$(git -C "${PROJECT_ROOT}" status --porcelain 2>/dev/null || printf '')"
pass_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
commit_cell="${commit}"
if [[ -n "${dirty_tree}" ]]; then
  # docs/REFERENCE-PASS.md: a pass is evidence about one commit. A dirty tree
  # means the figures below are not evidence about this one.
  commit_cell="${commit} — WORKING TREE DIRTY, these figures are not evidence about this commit alone"
  blocking+=("the working tree was dirty when the pass ran")
fi

{
  [[ -z "${silicon_banner}" ]] || printf '%s\n\n' "${silicon_banner}"
  printf 'date (UTC)          %s\n' "${pass_date}"
  printf 'hardware model      %s\n' "${hardware_model}"
  printf 'chip                %s\n' "${chip_brand}"
  printf 'architecture        %s\n' "${architecture}"
  printf 'hw.optional.arm64   %s\n' "${arm64_optional}"
  printf 'proc_translated     %s\n' "${translated}"
  printf 'memory bytes        %s\n' "${memory_bytes}"
  printf 'logical CPUs        %s\n' "${logical_cpus}"
  printf 'perflevel0 (perf)   %s\n' "${performance_cpus}"
  printf 'perflevel1 (eff)    %s\n' "${efficiency_cpus}"
  printf 'macOS               %s (%s)\n' "${product_version}" "${build_version}"
  printf 'commit              %s\n' "${commit}"
  printf 'working tree        %s\n' "${dirty_tree:-clean}"
} >"${out}/identity.txt"

{
  printf 'REFERENCE_PASS_DATE=%s\n' "${pass_date}"
  printf 'REFERENCE_PASS_MODEL=%s\n' "${hardware_model}"
  printf 'REFERENCE_PASS_ARCH=%s\n' "${architecture}"
  printf 'REFERENCE_PASS_MACOS=%s\n' "${product_version}"
  printf 'REFERENCE_PASS_BUILD=%s\n' "${build_version}"
  printf 'REFERENCE_PASS_COMMIT=%s\n' "${commit}"
} >"${out}/identity.env"

add_fill '| **Machine** |' "${hardware_model} · ${chip_brand} · ${memory_bytes} bytes RAM · ${logical_cpus} logical CPUs (${performance_cpus}P + ${efficiency_cpus}E)"
add_fill '| **macOS build** |' "${product_version} (${build_version})"
add_fill '| **Date of pass** |' "${pass_date}"
add_fill '| **Commit under test** |' "${commit_cell}"

# git-lfs guard. docs/RELEASE-GATES.md fixes the count at 10; an unresolved
# pointer still compiles, so a release can ship 132 bytes of text where an icon
# belongs.
lfs_count="$(git -C "${PROJECT_ROOT}" lfs ls-files | wc -l | tr -d ' ')"
if [[ "${lfs_count}" != "10" ]]; then
  blocking+=("git lfs ls-files listed ${lfs_count} files, not 10")
fi
add_fill '| **git-lfs objects present** |' "\`git lfs ls-files\` must list 10 · result: ${lfs_count}"

# The same icon-pointer probe scripts/release.sh runs, repeated verbatim so the
# two guards cannot drift: one file at a time, because a partially materialised
# checkout is exactly what a single-file probe waves through.
icon_directory="${PROJECT_ROOT}/Fathom/Resources/Assets.xcassets/AppIcon.appiconset"
icons_checked=0
for icon_path in "${icon_directory}"/*.png; do
  [[ -f "${icon_path}" ]] || continue
  icons_checked=$((icons_checked + 1))
  icon_header="$(head -c 64 -- "${icon_path}")"
  case "${icon_header}" in
    *git-lfs.github.com*)
      blocking+=("unresolved Git LFS pointer: ${icon_path}")
      ;;
    *)
      ;;
  esac
done
[[ "${icons_checked}" -gt 0 ]] ||
  blocking+=("no app icons found in ${icon_directory}")

# `diskutil` is banned in the shipping app — production reads the API — and the
# CI audit that enforces that greps Fathom, FathomKit and FathomBar for Swift.
# This is a record of the machine under test, written to a file the app never
# reads. Nothing here feeds a rendered value.
df -k "${volume}" >"${out}/gate1/free-space-before.txt"
diskutil info -plist "${volume}" >"${out}/gate1/volume-info.plist" 2>/dev/null || true
device_identifier="not published"
media_name="not published"
bus_protocol="not published"
filesystem_type="not published"
total_size="not published"
if [[ -s "${out}/gate1/volume-info.plist" ]]; then
  device_identifier="$(plutil -extract DeviceIdentifier raw -o - "${out}/gate1/volume-info.plist" 2>/dev/null || printf 'not published')"
  media_name="$(plutil -extract MediaName raw -o - "${out}/gate1/volume-info.plist" 2>/dev/null || printf 'not published')"
  bus_protocol="$(plutil -extract BusProtocol raw -o - "${out}/gate1/volume-info.plist" 2>/dev/null || printf 'not published')"
  filesystem_type="$(plutil -extract FilesystemType raw -o - "${out}/gate1/volume-info.plist" 2>/dev/null || printf 'not published')"
  total_size="$(plutil -extract TotalSize raw -o - "${out}/gate1/volume-info.plist" 2>/dev/null || printf 'not published')"
fi
add_fill '| **Volume, capacity, filesystem** |' "${volume} · ${total_size} bytes · ${filesystem_type}"
add_fill '| **Drive model and node** |' "${media_name} · /dev/${device_identifier} · ${bus_protocol}"

free_before="$(awk 'NR==2 {print $4}' "${out}/gate1/free-space-before.txt")"
add_fill '| Free space before the run | — |' "${free_before} KiB free before the run"

# ------------------------------------------------------------------ build ---

# Its own scratch path, never the repository's .build: a reference pass must not
# leave the checkout in a state the next command inherits.
scratch="${out}/swiftpm"
run swift build -c release --product fathom --scratch-path "${scratch}" \
  2>&1 | tee "${out}/logs/swift-build.log"
bin_path="$(swift build -c release --product fathom --scratch-path "${scratch}" --show-bin-path)"
fathom_bin="${bin_path}/fathom"
[[ -x "${fathom_bin}" ]] || fail "the release CLI did not build at ${fathom_bin}" 3

test_result="passed"
if ! swift test --scratch-path "${scratch}" >"${out}/logs/swift-test.log" 2>&1; then
  test_result="FAILED — see logs/swift-test.log"
  blocking+=("swift test failed on the reference machine")
fi

# Gate 1 without Full Disk Access measures a partial walk, so this is checked
# before anything is timed rather than explained afterwards. The exact rendering
# comes from FathomCLI's renderBoolean: "granted [...]" or "not granted [...]".
"${fathom_bin}" doctor >"${out}/logs/doctor-before.log" 2>&1
full_disk_access="$(sed -n 's/^Full Disk Access: //p' "${out}/logs/doctor-before.log" | head -1)"
case "${full_disk_access}" in
  granted*)
    ;;
  *)
    fail "Full Disk Access is ${full_disk_access:-not reported}; grant it to the terminal running this script (System Settings → Privacy & Security → Full Disk Access) — gate 1 without it is a measurement of a partial walk" 3
    ;;
esac

# ------------------------------------------------------ GATE 2, FIRST -------
#
# This order is the point of the script. A 30-second full-volume scan moves the
# NVMe data_units_read counter, warms the drive and changes the IOReport energy
# picture, so gate 1 would contaminate gate 2's readings. More importantly gate
# 2 is the only irreplaceable step here: if anything later goes wrong, the
# one-shot capture is already on disk.

printf 'reference-pass: gate 2 — capturing the raw hardware payloads first\n'
capture_status=0
if ! FATHOM_REFERENCE_COMMIT="${commit}" "${fathom_bin}" capture-fixtures \
  "${out}/fixtures/raw" >"${out}/logs/capture.log" 2>&1; then
  capture_status=$?
fi
if [[ "${capture_status}" -ne 0 ]]; then
  blocking+=("fathom capture-fixtures exited ${capture_status}; the one-shot payloads were not recorded")
fi
sed -n 's/^capture-fixtures: //p' "${out}/logs/capture.log" || true

"${fathom_bin}" doctor >"${out}/fixtures/doctor.txt" 2>&1
# dump-channels exits 0 whether or not IOReport publishes anything, so its
# status cannot tell a captured inventory from an empty one. Read the first
# line instead.
"${fathom_bin}" dump-channels >"${out}/fixtures/channels.tsv" 2>&1
channels_first_line="$(head -1 "${out}/fixtures/channels.tsv")"
case "${channels_first_line}" in
  'not published — '*)
    printf 'reference-pass: IOReport channel inventory %s\n' "${channels_first_line}" >&2
    ;;
  *)
    ;;
esac

# plutil -p beside each plist, so the evidence is readable by eye a year later
# without this toolchain.
for payload in "${out}/fixtures/raw"/*.plist; do
  [[ -f "${payload}" ]] || continue
  plutil -p "${payload}" >"${payload}.txt" 2>&1 || true
done

manifest="${out}/fixtures/raw/capture-manifest.json"
# Reads one payload's state out of the capture manifest.
#
# Through python3 rather than awk or sed: the manifest is JSON, this repository
# already depends on python3 for two CI gates, and a hand-rolled parser here
# would be a second place the manifest's shape is encoded. The first version of
# this function was that hand-rolled parser and it was already wrong — it looked
# for byteCount after name, and JSONEncoder's sortedKeys puts byteCount first,
# so every byte count came back empty.
payload_state() {
  PAYLOAD_CELL="${OPERATOR}"
  [[ -f "${manifest}" ]] || return 0
  PAYLOAD_CELL="$(python3 - "${manifest}" "$1" <<'PYTHON'
import json
import sys

manifest_path, wanted = sys.argv[1], sys.argv[2]
try:
    with open(manifest_path) as handle:
        payloads = json.load(handle)["payloads"]
except (OSError, ValueError, KeyError) as error:
    print("_not measured — capture-manifest.json unreadable: %s_" % error)
    raise SystemExit(0)

for payload in payloads:
    if payload.get("name") != wanted:
        continue
    if payload.get("state") == "captured":
        print("yes, %s bytes" % payload.get("byteCount"))
    else:
        print("%s — %s" % (payload.get("state"), payload.get("reason")))
    raise SystemExit(0)

print("_not measured — capture-manifest.json names no payload %s_" % wanted)
PYTHON
)"
  [[ -n "${PAYLOAD_CELL}" ]] || PAYLOAD_CELL="${OPERATOR}"
}

payload_state 'nvme-smart-log-page.bin'
nvme_payload="${PAYLOAD_CELL}"
payload_state 'smc-key-inventory.json'
smc_inventory_payload="${PAYLOAD_CELL}"
payload_state 'smc-key-values.json'
smc_values_payload="${PAYLOAD_CELL}"
payload_state 'ioreport-subscribed-channels.plist'
ioreport_subscription_payload="${PAYLOAD_CELL}"

# `Committed as` stays "not yet committed": installing fixtures into
# FathomKitTests is a reviewed change to the repository, not something a
# measurement script does behind the operator.
readonly NOT_COMMITTED='not yet committed — copy from fixtures/raw into FathomKitTests/Fixtures in a reviewed change'
add_fill '| NVMe SMART log page, raw bytes |' "${nvme_payload}" "${NOT_COMMITTED}"
add_fill '| SMC key inventory |' "${smc_inventory_payload}" "${NOT_COMMITTED}"
add_fill '| SMC key values read |' "${smc_values_payload}" "${NOT_COMMITTED}"
add_fill '| IOReport channel subscription |' "${ioreport_subscription_payload}" "${NOT_COMMITTED}"

# Gate 2's comparison rows, keyed on the exact strings FathomCLI prints.
doctor_value() {
  DOCTOR_VALUE="$(sed -n "s/^$1//p" "${out}/fixtures/doctor.txt" | head -1)"
  [[ -n "${DOCTOR_VALUE}" ]] || DOCTOR_VALUE="${OPERATOR}"
}

# The monotone counters cannot be compared literally. FATHOM-DATA-SOURCES.md's
# figures are a 29 July 2026 reading of counters that only ever increase, so an
# equality check is guaranteed to report a finding that is not one.
readonly MONOTONE='monotone — not a comparison'

doctor_value 'NVMe SMART percentage used: '
add_fill '| NVMe SMART | Percentage used |' '5% on 29 Jul 2026; rises only' "${DOCTOR_VALUE}" "${OPERATOR}"
doctor_value 'NVMe SMART bytes written: '
add_fill '| NVMe SMART | Data written |' '≥ 149.97 TB (monotone; recorded 29 Jul 2026)' "${DOCTOR_VALUE}" "${MONOTONE}"
doctor_value 'NVMe SMART power-on hours: '
add_fill '| NVMe SMART | Power-on hours |' '≥ 1,925 (monotone; recorded 29 Jul 2026)' "${DOCTOR_VALUE}" "${MONOTONE}"
doctor_value 'NVMe SMART unsafe shutdowns: '
add_fill '| NVMe SMART | Unsafe shutdowns |' '≥ 43 (monotone; recorded 29 Jul 2026)' "${DOCTOR_VALUE}" "${MONOTONE}"
doctor_value 'SMC PSTR: '
add_fill "| SMC | Total system power (\`PSTR\`) |" 'published in watts; FATHOM-DATA-SOURCES.md states no figure' "${DOCTOR_VALUE}" "${OPERATOR}"
doctor_value 'SMC fan speed keys: '
add_fill '| SMC | Fan keys |' 'at least one; FATHOM-DATA-SOURCES.md records Fan #0 on the M4 Pro' "${DOCTOR_VALUE}" "${OPERATOR}"
doctor_value 'IOHID temperatures: '
add_fill '| IOHID | Temperature sensor count |' 'per-core CPU, GPU 1–8, memory proximity, NAND, Airport per FATHOM-DATA-SOURCES.md; no count is stated' "${DOCTOR_VALUE}" "${OPERATOR}"
doctor_value 'IOReport energy sample: '
add_fill '| IOReport | Power channels published |' 'CPU, GPU, ANE, RAM, PCI and average system total' "${DOCTOR_VALUE}" "${OPERATOR}"

( cd "${out}/fixtures" && find . -type f | sort | xargs shasum -a 256 ) \
  >"${out}/fixtures/SHA256SUMS" 2>/dev/null || true

# ------------------------------------------------------------- GATE 1 -------

duration_cell="${OPERATOR}"
churn_cell="${OPERATOR}"
resident_cell="${OPERATOR}"
index_peak_cell="${OPERATOR}"
if [[ "${skip_benchmark}" == true ]]; then
  duration_cell='_skipped — --skip-benchmark_'
  churn_cell="${duration_cell}"
  resident_cell="${duration_cell}"
  index_peak_cell="${duration_cell}"
else
  # Resolve the index path the way Foundation resolves it, not the way the docs
  # read. Measured: FileManager.default.temporaryDirectory ignores TMPDIR on
  # macOS and returns getconf DARWIN_USER_TEMP_DIR, so exporting TMPDIR here
  # would move nothing and the sampler would watch an empty path.
  index_dir="$(getconf DARWIN_USER_TEMP_DIR)"
  index_dir="${index_dir%/}/"
  index_path="${index_dir}fathom-benchmark.sqlite"

  # StorageIndex opens CREATE|READWRITE and silently reuses whatever is there,
  # so a second run on the same machine would time an incremental update and
  # report a peak size that belongs to the previous pass. Moved, never removed:
  # this repository's attitude is that things are recoverable, not destroyed.
  if [[ -e "${index_path}" ]]; then
    run mkdir -p -- "${out}/gate1/stale-index"
    for stale in "${index_path}" "${index_path}-wal" "${index_path}-shm"; do
      [[ -e "${stale}" ]] || continue
      run mv -- "${stale}" "${out}/gate1/stale-index/"
    done
    printf 'a stale benchmark index was moved aside before this run\n' \
      >"${out}/gate1/stale-index/README.txt"
  fi

  samples_file="${out}/gate1/index-size-samples.tsv"
  : >"${samples_file}"
  (
    while :; do
      sample_total=0
      for part in "${index_path}" "${index_path}-wal" "${index_path}-shm"; do
        part_size="$(stat -f %z "${part}" 2>/dev/null || printf '0')"
        sample_total=$((sample_total + part_size))
      done
      sample_at="$(date +%s)"
      printf '%s\t%s\n' "${sample_at}" "${sample_total}" >>"${samples_file}"
      sleep 0.5
    done
  ) &
  sampler_pid=$!

  benchmark_started="$(date +%s)"
  benchmark_status=0
  if ! "${fathom_bin}" benchmark "${volume}" --enforce-reference-gates \
    >"${out}/gate1/benchmark.log" 2>&1; then
    benchmark_status=$?
  fi
  benchmark_ended="$(date +%s)"
  cleanup

  if [[ "${benchmark_status}" -ne 0 ]]; then
    blocking+=("fathom benchmark --enforce-reference-gates exited ${benchmark_status}")
  fi

  index_peak_bytes="$(sort -k2 -n "${samples_file}" | tail -1 | awk '{print $2}')"
  index_peak_bytes="${index_peak_bytes:-0}"
  benchmark_seconds=$((benchmark_ended - benchmark_started))
  # Gate 1's newest figure is the one nothing enforces, so a zero has to be
  # loud. The index path is a hard-coded literal inside FathomCLI; if that ever
  # gains an option, this sampler watches an empty path and reports a peak of
  # nothing while looking like it worked.
  if [[ "${index_peak_bytes}" -eq 0 && "${benchmark_seconds}" -gt 1 ]]; then
    blocking+=("the benchmark index was never observed at ${index_path}; peak index size is unmeasured, not zero")
    index_peak_cell='UNMEASURED — the sampler never saw an index at the expected path'
  else
    index_peak_cell="${index_peak_bytes} bytes peak (index + -wal + -shm, sampled every 0.5 s)"
  fi

  benchmark_value() {
    BENCHMARK_VALUE="$(sed -n "s/^$1//p" "${out}/gate1/benchmark.log" | head -1)"
    [[ -n "${BENCHMARK_VALUE}" ]] || BENCHMARK_VALUE="${OPERATOR}"
  }
  # The gate is a rate now, but the duration and the entry count are what a
  # human reads it against, so the cell carries all three.
  benchmark_value 'entries/second: '
  rate_value="${BENCHMARK_VALUE}"
  benchmark_value 'entries: '
  entries_value="${BENCHMARK_VALUE}"
  benchmark_value 'duration: '
  duration_cell="${rate_value} entries/s (${entries_value} entries in ${BENCHMARK_VALUE})"
  benchmark_value 'changed during the scan: '
  churn_cell="${BENCHMARK_VALUE}"
  benchmark_value 'peak resident bytes: '
  resident_cell="${BENCHMARK_VALUE}"
  gates_line="$(grep -c '^reference gates: PASS$' "${out}/gate1/benchmark.log" || true)"
  if [[ "${gates_line}" == "0" ]]; then
    duration_cell="${duration_cell} — the CLI did not print 'reference gates: PASS'"
  fi
  df -k "${volume}" >"${out}/gate1/free-space-after.txt"
fi

add_fill '| Scan rate | at least 18,000 entries/s; under 12,000 blocks |' "${duration_cell}"
add_fill '| Files changed during the scan | recorded, never budgeted |' "${churn_cell}"
add_fill '| Peak resident memory | under 300 MB |' "${resident_cell}"
add_fill '| Peak index size on disk | no budget; **record it** |' "${index_peak_cell}"

# ------------------------------------------------------------- GATE 3 -------

widget_cpu_cell="${OPERATOR}"
widget_items_cell="${OPERATOR}"
bar_app=""
build_provenance="unsigned Release build from this run"

# The scheme is named FathomBar and the bundle it produces is "FATHOM Bar.app".
# Assuming the scheme name here cost every reference pass its gate 3: the build
# succeeded, the bundle was looked for under the wrong name, and the record said
# "no FathomBar bundle to measure" as though the widget were the problem. Ask
# the build system what it produced instead of guessing.
bar_bundle_name="$(
  xcodebuild -project "${PROJECT_ROOT}/Fathom.xcodeproj" \
    -scheme FathomBar -configuration Release -showBuildSettings 2>/dev/null |
    awk -F' = ' '/ FULL_PRODUCT_NAME = /{print $2; exit}'
)"
[[ -n "${bar_bundle_name}" ]] || bar_bundle_name='FATHOM Bar.app'
printf '%s\n' "${bar_bundle_name}" >"${out}/gate3/bundle-name.txt"

if [[ -n "${signed_app}" ]]; then
  build_provenance="the bundle passed to --signed-app"
  find "${signed_app}" -name "${bar_bundle_name}" \
    >"${out}/gate3/bar-candidates.txt" 2>/dev/null || true
  bar_app="$(head -1 "${out}/gate3/bar-candidates.txt")"
else
  run xcodegen generate --spec "${PROJECT_ROOT}/project.yml"
  run xcodebuild -quiet -project "${PROJECT_ROOT}/Fathom.xcodeproj" \
    -scheme FathomBar -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${out}/build-dd" \
    CODE_SIGNING_ALLOWED=NO build
  bar_app="${out}/build-dd/Build/Products/Release/${bar_bundle_name}"

  # A build that succeeded and then produced nothing to measure is this
  # script's bug, not a gate outcome. Recording it as an unmeasured gate is
  # how the wrong name survived several passes.
  [[ -d "${bar_app}" ]] ||
    fail "FathomBar built but ${bar_app} is not there; the bundle name this script looks for is wrong" 3
fi

if [[ -z "${bar_app}" || ! -d "${bar_app}" ]]; then
  blocking+=("no ${bar_bundle_name} in the bundle passed to --signed-app; gate 3 is unmeasured")
else
  defaults read com.exhibinaut.fathom.shared \
    >"${out}/gate3/defaults-before.txt" 2>/dev/null ||
    printf 'no shared domain yet\n' >"${out}/gate3/defaults-before.txt"
  for item_key in bar.freeSpace bar.hottestSensor bar.networkThroughput bar.cpuLoad; do
    run defaults write com.exhibinaut.fathom.shared "${item_key}" -bool YES
  done

  # The published figure carries a timeIntervalSinceReferenceDate, so this run's
  # reading can be told from a months-old one without deleting anything. 978307201
  # is the Unix epoch of 2001-01-01 plus a second of margin against clock skew.
  now_unix="$(date +%s)"
  started_reference=$((now_unix - 978307201))
  run open "${bar_app}"
  waited=0
  measured_at=""
  while [[ "${waited}" -lt "${bar_wait}" ]]; do
    measured_at="$(defaults read com.exhibinaut.fathom.shared bar.measuredIdleAt 2>/dev/null || printf '')"
    if [[ -n "${measured_at}" ]]; then
      # Integer compare against the truncated value; the widget needs two
      # samples on a 5 s loop before it publishes anything at all.
      measured_whole="${measured_at%%.*}"
      if [[ "${measured_whole}" =~ ^[0-9]+$ ]] &&
        [[ "${measured_whole}" -gt "${started_reference}" ]]; then
        break
      fi
    fi
    measured_at=""
    sleep 5
    waited=$((waited + 5))
  done

  if [[ -z "${measured_at}" ]]; then
    blocking+=("FathomBar published no idle-cost figure within ${bar_wait} s")
  else
    widget_cpu="$(defaults read com.exhibinaut.fathom.shared bar.measuredIdleCPUPercent 2>/dev/null || printf '')"
    widget_items="$(defaults read com.exhibinaut.fathom.shared bar.measuredIdleItemCount 2>/dev/null || printf '')"
    {
      printf 'widget CPU percent  %s\n' "${widget_cpu}"
      printf 'items shown         %s\n' "${widget_items}"
      printf 'measured at (ref)   %s\n' "${measured_at}"
      printf 'build               %s\n' "${build_provenance}"
    } >"${out}/gate3/idle-cost.txt"
    widget_cpu_cell="${widget_cpu}% (${build_provenance})"
    widget_items_cell="${widget_items}"
    # 0.5% blocks the release; 0.2% is the target. Compared in hundredths
    # because bash 3.2 has no floating point.
    cpu_hundredths="$(awk -v value="${widget_cpu}" 'BEGIN { printf "%d", value * 100 }')"
    if [[ "${cpu_hundredths}" -ge 50 ]]; then
      blocking+=("FathomBar idle CPU is ${widget_cpu}%, at or over the 0.5% blocking threshold")
    fi
    if [[ "${widget_items}" != "4" ]]; then
      blocking+=("FathomBar published its cost with ${widget_items} items, not 4; the target is stated for four and fewer measures a different thing")
    fi
  fi
fi

add_fill '| Widget CPU | ≤ 0.2% | 0.5% |' "${widget_cpu_cell}" "${widget_items_cell}"
add_fill '| Energy Impact | ≤ 2.1 | 4.0 |' '_not measured — Activity Monitor, by hand_' '—'

# --------------------------------------------- gate 5 and Distribution ------

assess_target="${signed_app}"
[[ -n "${assess_target}" ]] || assess_target="${out}/build-dd/Build/Products/Release/FATHOM.app"
if [[ -d "${assess_target}" ]]; then
  codesign -dv --verbose=4 "${assess_target}" >"${out}/gate5/codesign.txt" 2>&1 || true
  spctl --assess --type execute --verbose=2 "${assess_target}" \
    >"${out}/gate5/spctl.txt" 2>&1 || true
else
  printf 'no bundle to assess\n' >"${out}/gate5/codesign.txt"
  cp "${out}/gate5/codesign.txt" "${out}/gate5/spctl.txt"
fi

security find-identity -v -p codesigning \
  >"${out}/distribution/identities.txt" 2>&1 || true
identity_summary="$(tail -1 "${out}/distribution/identities.txt")"
add_fill "| \`security find-identity -v -p codesigning\` |" "${identity_summary}"

notary_cell='not configured — FATHOM_NOTARY_PROFILE was not set'
if [[ -n "${FATHOM_NOTARY_PROFILE:-}" ]]; then
  if xcrun notarytool history --keychain-profile "${FATHOM_NOTARY_PROFILE}" \
    >"${out}/distribution/notary-history.txt" 2>&1; then
    notary_cell="profile ${FATHOM_NOTARY_PROFILE} answered; see distribution/notary-history.txt"
  else
    notary_cell="profile ${FATHOM_NOTARY_PROFILE} did not answer; see distribution/notary-history.txt"
  fi
fi
add_fill "| \`notarytool\` profile configured |" "${notary_cell}"

# The remaining three Distribution rows belong to scripts/release.sh, which is
# the only signing path in this repository and is not reimplemented here.
add_fill '| Signed, stapled app |' '_scripts/release.sh — not run by this script_'
add_fill '| Signed, stapled DMG |' '_scripts/release.sh — not run by this script_'
add_fill '| Gatekeeper assessment |' '_scripts/release.sh — not run by this script_; this run recorded gate5/spctl.txt'

# ------------------------------------------- rows only a person can fill ----

gate5_note="${OPERATOR}"
if [[ -z "${signed_app}" ]]; then
  # Gate 5 asks for the signed, hardened, notarized build. An unsigned Release
  # build is a measurement of a different binary, and the record must never let
  # one stand in for the other.
  gate5_note='_not measured — requires --signed-app; an unsigned build measures a different binary_'
fi
for human_row in \
  '| Onboarding |' \
  '| Menu-bar visibility guidance |' \
  '| Sleep/wake suspension |' \
  '| Memory-pressure second row |' \
  '| VoiceOver, per view |' \
  '| Keyboard navigation and focus ring |' \
  '| Dynamic Type to Accessibility Large |' \
  '| Reduce Motion |' \
  '| The plate reads correctly on a real display |' \
  '| Every section keeps updating after a switch |' \
  '| Bluetooth populates on entry, no *not published* flash |' \
  '| Leaving Bluetooth stops the reads |'; do
  add_fill "${human_row}" "${OPERATOR}"
done
for gate5_row in \
  '| Consent prompt appears |' \
  '| App survives the prompt |' \
  '| Paired devices publish after granting |' \
  '| Cold Bluetooth read, ms (first read only) |' \
  '| If denied: the exact denial observed |'; do
  add_fill "${gate5_row}" "${gate5_note}"
done

add_fill '| **All gates recorded** |' "gates 1 to 3 and Distribution mechanically; gates 4, 5 and 6 await the operator"
if [[ "${#blocking[@]}" -eq 0 ]]; then
  add_fill '| **Blocking failures** |' 'none from the mechanical pass'
else
  blocking_joined="$(printf '%s; ' "${blocking[@]}")"
  add_fill '| **Blocking failures** |' "${blocking_joined%; }"
fi
add_fill '| **Issues opened** |' "${OPERATOR}"
add_fill '| **Cleared for release** |' "${OPERATOR}"

# ------------------------------------------------------- the filled form ----

record="${out}/REFERENCE-PASS.md"
# Keyed on FILENAME rather than the usual NR == FNR: with an empty fills file
# that idiom is true for the form's first line too, and the record would lose
# its title to a rule meant for a different file.
awk -F'\t' -v banner="${silicon_banner}" -v fills="${fills_file}" '
  FILENAME == fills { key[FNR] = $1; row[FNR] = $2; keys = FNR; next }
  FNR == 1 && banner != "" { print "```"; print banner; print "```"; print "" }
  {
    best = 0
    for (i = 1; i <= keys; i++) {
      if (substr($0, 1, length(key[i])) == key[i] &&
          length(key[i]) > length(key[best])) {
        best = i
      }
    }
    if (best > 0) { print row[best]; used[best] = 1 }
    else { print $0 }
  }
  END {
    for (i = 1; i <= keys; i++) {
      if (!(i in used)) {
        print "UNMATCHED\t" key[i] > "/dev/stderr"
      }
    }
  }
' "${fills_file}" "${FORM}" >"${record}" 2>"${out}/logs/unmatched-rows.txt"

if [[ -s "${out}/logs/unmatched-rows.txt" ]]; then
  # A row key that no longer matches leaves a blank cell, and a blank cell in
  # this form means *not measured* — the record would understate itself
  # silently. Say so rather than shipping it.
  blocking+=("$(wc -l <"${out}/logs/unmatched-rows.txt" | tr -d ' ') row keys no longer match docs/REFERENCE-PASS.md; see logs/unmatched-rows.txt")
fi

{
  printf '\n---\n\n## Machine-captured evidence\n\n'
  printf "Recorded by \`scripts/reference-pass.sh\` %s at %s.\n\n" \
    "${SCRIPT_VERSION}" "${pass_date}"
  printf '```\n'
  cat "${out}/identity.txt"
  printf '\nswift test: %s\n' "${test_result}"
  printf '```\n\n'
  printf 'Files, with SHA-256 where the capture recorded one:\n\n```\n'
  cat "${out}/fixtures/SHA256SUMS" 2>/dev/null || printf 'none\n'
  printf '```\n\n'
  printf 'Capture manifest:\n\n```json\n'
  cat "${manifest}" 2>/dev/null || printf 'not written\n'
  printf '\n```\n\n'
  printf '## What this run did not settle\n\n'
  printf 'Every row below still needs a person at this machine.\n\n'
  printf '%s\n' \
    '1. Energy Impact, from Activity Monitor. The composite needs root and' \
    '   FATHOM does not take root to report on itself.' \
    '2. All ten gate-4 accessibility rows. Turn Full Keyboard Access ON first:' \
    '   no focus ring has ever been seen where focus actually puts it.' \
    '3. Gate 5 against the signed, hardened, notarized build — the consent' \
    '   prompt, whether the app survives it, and the exact denial if denied.' \
    '4. The cold Bluetooth read. Record the first read against the median of' \
    '   the reads after it: the ten-second deadline rests on one 5,777 ms' \
    '   sample.' \
    '5. Gate 6 — walk CPU → Bluetooth → CPU → Memory and back, and confirm' \
    '   every section keeps updating after a switch.' \
    '6. Walk all twenty sections with the arrow keys, on a real display.'
} >>"${record}"

printf '\n'
printf 'reference-pass: record written to %s\n' "${record}"
printf 'reference-pass: evidence in %s\n' "${out}"
printf '\n'
printf 'reference-pass: still needs a person, in the form'"'"'s own row order:\n'
printf '%s\n' \
  ' 1. Gate 3 — Energy Impact from Activity Monitor (target 2.1, blocks at 4.0)' \
  ' 2. Gate 4 — onboarding, menu-bar guidance, sleep/wake suspension' \
  ' 3. Gate 4 — memory-pressure second row, VoiceOver on every view' \
  ' 4. Gate 4 — Full Keyboard Access ON, then the focus ring on every control' \
  ' 5. Gate 4 — Dynamic Type to Accessibility Large, and Reduce Motion' \
  ' 6. Gate 4 — the plate, and .ultraThinMaterial behind the rail and under' \
  '             Reclaim'"'"'s journal-recovery banner, on a real display' \
  ' 7. Gate 5 — the Bluetooth consent prompt against the signed build' \
  ' 8. Gate 5 — time the cold Bluetooth read against the median after it' \
  ' 9. Gate 6 — CPU → Bluetooth → CPU → Memory and back' \
  '10. Outcome — issues opened, and whether this is cleared for release'

if [[ "${#blocking[@]}" -ne 0 ]]; then
  printf '\n'
  printf 'reference-pass: %d blocking failure(s):\n' "${#blocking[@]}"
  printf 'reference-pass:   %s\n' "${blocking[@]}"
  exit 5
fi

printf '\nreference-pass: no blocking failures from the mechanical pass\n'
