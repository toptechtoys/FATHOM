#!/usr/bin/env bats

@test "release help documents credentials and outputs" {
  run bash scripts/release.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"FATHOM_DEVELOPER_ID_APPLICATION"* ]]
  [[ "$output" == *"FATHOM-VERSION.dmg"* ]]
}

@test "release rejects malformed versions before doing work" {
  run env \
    FATHOM_DEVELOPER_ID_APPLICATION=test \
    FATHOM_NOTARY_PROFILE=test \
    bash scripts/release.sh --release-version latest --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"must match X.Y.Z"* ]]
}

# The regression for the defect that mattered most: the credential guards were
# written as `: "${VAR:?message}"`, and the EXIT trap reset that abort to 0, so
# the script reported success having built nothing. Nothing covered this path
# because both tests above always set both variables.
@test "release refuses to run without credentials" {
  run env \
    -u FATHOM_DEVELOPER_ID_APPLICATION \
    -u FATHOM_NOTARY_PROFILE \
    bash scripts/release.sh --release-version 1.0.0 --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"FATHOM_DEVELOPER_ID_APPLICATION"* ]]
}

@test "release names the missing notary profile on its own" {
  run env \
    -u FATHOM_NOTARY_PROFILE \
    FATHOM_DEVELOPER_ID_APPLICATION=test \
    bash scripts/release.sh --release-version 1.0.0 --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"FATHOM_NOTARY_PROFILE"* ]]
}

# The disk image was never signed, so the Gatekeeper assessment on the script's
# last line could not pass — and it failed there after two notarization round
# trips. The ordering is the whole point: signing must precede submission.
@test "release signs the disk image before submitting it" {
  run env \
    FATHOM_DEVELOPER_ID_APPLICATION=test \
    FATHOM_NOTARY_PROFILE=test \
    bash scripts/release.sh --release-version 1.2.3 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"codesign --force --sign test --timestamp --identifier com.exhibinaut.fathom.dmg"* ]]
  sign_line="$(printf '%s\n' "$output" | grep -n -- '--identifier com.exhibinaut.fathom.dmg' | head -1 | cut -d: -f1)"
  submit_line="$(printf '%s\n' "$output" | grep -n -- 'notarytool submit .*\.dmg' | head -1 | cut -d: -f1)"
  [ -n "$sign_line" ]
  [ -n "$submit_line" ]
  [ "$sign_line" -lt "$submit_line" ]
}

# Xcode decides `--timestamp` versus `--timestamp=none` internally and exposes
# no way to read the decision back, so the archive asks for it explicitly. A
# signature without a secure timestamp is rejected by the notary service.
@test "release asks for a secure timestamp at archive time" {
  run env \
    FATHOM_DEVELOPER_ID_APPLICATION=test \
    FATHOM_NOTARY_PROFILE=test \
    bash scripts/release.sh --release-version 1.2.3 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"OTHER_CODE_SIGN_FLAGS=--timestamp"* ]]
}

@test "release runs Gatekeeper on both artefacts" {
  run env \
    FATHOM_DEVELOPER_ID_APPLICATION=test \
    FATHOM_NOTARY_PROFILE=test \
    bash scripts/release.sh --release-version 1.2.3 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"spctl --assess --type execute"* ]]
  [[ "$output" == *"spctl --assess --type open --context context:primary-signature"* ]]
}

# A run that fails at notarization leaves dist/FATHOM-X.Y.Z.xcarchive behind, so
# this guard is what the owner meets on the retry. It has to say what to remove.
@test "release refuses to overwrite an existing artefact" {
  touch "$BATS_TEST_TMPDIR/FATHOM-1.2.3.dmg"
  run env \
    FATHOM_DEVELOPER_ID_APPLICATION=test \
    FATHOM_NOTARY_PROFILE=test \
    bash scripts/release.sh --release-version 1.2.3 --dry-run --output "$BATS_TEST_TMPDIR"
  [ "$status" -eq 4 ]
  [[ "$output" == *"refusing to overwrite"* ]]
  [[ "$output" == *"rerun"* ]]
}

@test "release reports its own version and rejects bad arguments" {
  run bash scripts/release.sh --version
  [ "$status" -eq 0 ]
  [[ "$output" == "1.0.0" ]]

  run bash scripts/release.sh --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]

  run bash scripts/release.sh --release-version
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value"* ]]
}
