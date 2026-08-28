#!/usr/bin/env bats

@test "reference-pass help documents the exit codes and the record it fills" {
  run bash scripts/reference-pass.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFERENCE-PASS.md"* ]]
  [[ "$output" == *"capture-fixtures"* ]]
  [[ "$output" == *"0 success"* ]]
  [[ "$output" == *"2 invalid input"* ]]
  [[ "$output" == *"3 missing prerequisite"* ]]
  [[ "$output" == *"4 output exists"* ]]
  [[ "$output" == *"5 a gate failed"* ]]
  [[ "$output" == *"6 not Apple silicon"* ]]
}

@test "reference-pass help says a not-published reading is not a failure" {
  run bash scripts/reference-pass.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"an outcome, not a failure"* ]]
}

@test "reference-pass reports its own version and rejects bad arguments" {
  run bash scripts/reference-pass.sh --version
  [ "$status" -eq 0 ]
  [[ "$output" == "1.0.0" ]]

  run bash scripts/reference-pass.sh --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]

  run bash scripts/reference-pass.sh --output
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value"* ]]

  run bash scripts/reference-pass.sh --volume
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value"* ]]

  run bash scripts/reference-pass.sh --bar-wait soon
  [ "$status" -eq 2 ]
  [[ "$output" == *"whole number of seconds"* ]]

  run bash scripts/reference-pass.sh --volume /no/such/volume
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a directory"* ]]
}

# The operator is at the reference machine once. A run that reports its plan is
# fine and then dies on its first mkdir has spent that visit for nothing, so the
# overwrite guard is checked before --dry-run returns rather than after.
@test "reference-pass refuses an existing output directory, even dry" {
  mkdir -p "$BATS_TEST_TMPDIR/already"
  run bash scripts/reference-pass.sh \
    --allow-non-apple-silicon --dry-run --output "$BATS_TEST_TMPDIR/already"
  [ "$status" -eq 4 ]
  [[ "$output" == *"refusing to overwrite"* ]]
}

@test "reference-pass --dry-run creates nothing" {
  run bash scripts/reference-pass.sh \
    --allow-non-apple-silicon --dry-run --output "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
  [[ "$output" == *"nothing is created and nothing is measured"* ]]
}

# The plan is printed rather than executed, so the ordering claim has to be
# checked in the printout: gate 2 is the only irreplaceable step, and a run that
# does gate 1 first contaminates the SMART counters it is about to record.
@test "reference-pass plans gate 2 before gate 1" {
  run bash scripts/reference-pass.sh \
    --allow-non-apple-silicon --dry-run --output "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  gate2_line="$(printf '%s\n' "$output" | grep -n 'GATE 2 FIRST' | head -1 | cut -d: -f1)"
  gate1_line="$(printf '%s\n' "$output" | grep -n 'GATE 1:' | head -1 | cut -d: -f1)"
  [ -n "$gate2_line" ]
  [ -n "$gate1_line" ]
  [ "$gate2_line" -lt "$gate1_line" ]
}

@test "reference-pass refuses a non-Apple-silicon host by default" {
  if [ "$(uname -m)" = arm64 ]; then
    skip "this host is Apple silicon; the refusal path cannot be exercised here"
  fi
  run bash scripts/reference-pass.sh --output "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 6 ]
  [[ "$output" == *"Apple silicon"* ]]
  [[ "$output" == *"measurement of something else"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
}

@test "reference-pass stamps the override with a banner nobody can miss" {
  if [ "$(uname -m)" = arm64 ]; then
    skip "this host is Apple silicon; there is no banner to print"
  fi
  run bash scripts/reference-pass.sh \
    --allow-non-apple-silicon --dry-run --output "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT APPLE SILICON"* ]]
}

@test "reference-pass passes the architecture gate on Apple silicon" {
  if [ "$(uname -m)" != arm64 ]; then
    skip "this host is not Apple silicon"
  fi
  run bash scripts/reference-pass.sh --dry-run --output "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [[ "$output" != *"NOT APPLE SILICON"* ]]
}

# The highest-value assertion in this file. The record filler matches literal
# leading cells of docs/REFERENCE-PASS.md rows, so the likeliest long-term
# failure is somebody rewording a row: the match stops, the cell comes back
# empty, and an empty cell in that form means *not measured*. The record would
# understate itself and read exactly like an honest blank.
@test "every row key the filler matches still exists in the form" {
  run bash scripts/reference-pass.sh --print-row-keys
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  missing=""
  count=0
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    count=$((count + 1))
    if ! grep -qF -- "$key" docs/REFERENCE-PASS.md; then
      missing="${missing}${key}"$'\n'
    fi
  done <<<"$output"

  [ "$count" -gt 40 ]
  [ -z "$missing" ] || {
    printf 'row keys no longer in docs/REFERENCE-PASS.md:\n%s' "$missing"
    false
  }
}

# --print-row-keys must not be a way to start a pass by accident: it is the
# introspection the test above depends on, and it runs before any gate.
@test "reference-pass --print-row-keys touches nothing and needs no hardware" {
  run bash scripts/reference-pass.sh --print-row-keys --output "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
  [[ "$output" == *"| Peak index size on disk | no budget; **record it** |"* ]]
}
