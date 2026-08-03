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
