#!/usr/bin/env python3
"""Prove every DataSource case is documented.

Non-negotiable 1 says a value that cannot be traced to a row in
FATHOM-DATA-SOURCES.md does not render. Until now that was enforced by review,
and review had missed three: `IOHIDEventSystemClient` temperature, the
`IOBlockStorageDriver` byte counters and `SF_DATALESS` were all rendering
values in the shipping UI with nothing behind them, for weeks, in the one rule
the product's whole position rests on.

So it is a gate now. This reads the raw value of every case in
`FathomKit/Model/DataSource.swift` -- that string is what the UI shows when a
reader asks a number where it came from -- and requires each one to appear in
the document's *source index*, spelled identically, naming a section that
exists. A case that ships without a row fails the build instead of waiting for
somebody to notice.

The index is checked in both directions. A row for a case that no longer exists
is a stale promise about a value nothing renders, and a section name with no
matching heading is a lookup that dead-ends, which is the failure this gate is
supposed to prevent one level down. Exits non-zero on any of them.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENUM = ROOT / "FathomKit/Model/DataSource.swift"
DOC = ROOT / "docs/FATHOM-DATA-SOURCES.md"
INDEX_HEADING = "## The source index"

# `case name = "value"`, with the value on the same line or wrapped onto the
# next one. Swift's line length wins that argument often enough here -- 45 of
# the 66 cases wrap -- that a same-line-only pattern would miss two thirds of
# the enum and report a clean run over the cases it never saw.
CASE = re.compile(r'^\s*case\s+(\w+)\s*=\s*\n?\s*"([^"]*)"', re.MULTILINE)

# | `case` | `provenance string` | Section |
ROW = re.compile(r"^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|\s*([^|]+?)\s*\|\s*$")

HEADING = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)


def main() -> int:
    enum_source = ENUM.read_text()
    doc = DOC.read_text()

    cases = CASE.findall(enum_source)
    if not cases:
        print(f"error: no cases parsed from {ENUM.name}", file=sys.stderr)
        return 2
    declared = dict(cases)
    if len(declared) != len(cases):
        print("error: duplicate case names in DataSource", file=sys.stderr)
        return 2

    if INDEX_HEADING not in doc:
        print(
            f"error: {DOC.name} has no '{INDEX_HEADING}' section to check "
            "against",
            file=sys.stderr,
        )
        return 2
    index_body = doc.split(INDEX_HEADING, 1)[1]

    sections = {name for name in HEADING.findall(doc)}
    sections.discard(INDEX_HEADING.removeprefix("## "))

    indexed: dict[str, tuple[str, str]] = {}
    for line in index_body.splitlines():
        match = ROW.match(line)
        if match:
            name, value, section = match.groups()
            indexed[name] = (value, section)

    undocumented = [n for n in declared if n not in indexed]
    misspelled = [
        (n, declared[n], indexed[n][0])
        for n in declared
        if n in indexed and indexed[n][0] != declared[n]
    ]
    stale = [n for n in indexed if n not in declared]
    dangling = [
        (n, indexed[n][1])
        for n in indexed
        if n in declared and indexed[n][1] not in sections
    ]

    if undocumented:
        print(
            f"error: {len(undocumented)} DataSource case(s) render a value "
            f"with no row in {DOC.name}:",
            file=sys.stderr,
        )
        for name in undocumented:
            print(f"  {name} = \"{declared[name]}\"", file=sys.stderr)
        print(
            "  add the row where the value belongs, then index it under "
            f"'{INDEX_HEADING}'",
            file=sys.stderr,
        )

    for name, expected, found in misspelled:
        print(
            f"error: {name} is indexed as \"{found}\" but renders "
            f"\"{expected}\"",
            file=sys.stderr,
        )

    for name in stale:
        print(
            f"error: the index carries {name}, which DataSource no longer "
            "declares",
            file=sys.stderr,
        )

    for name, section in dangling:
        print(
            f"error: {name} is documented in '{section}', which is not a "
            f"section of {DOC.name}",
            file=sys.stderr,
        )

    if undocumented or misspelled or stale or dangling:
        return 1

    print(
        f"{len(declared)} DataSource cases, {len(declared)} indexed rows, "
        f"{len(sections)} sections -- every rendered value traces to "
        f"{DOC.name}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
