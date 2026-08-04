#!/usr/bin/env python3
"""Measure body-text contrast against every colour world.

AGENTS.md requires contrast >= 4.5:1 on every surface, and FATHOM-DESIGN.md
names the worst case: "the bottom stop is the worst case, test there."

Both inputs are read from source rather than restated here, so this cannot drift
from what the app actually renders. Exits non-zero if any world fails.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / "Fathom/Design/FathomDesign.swift"
TEXT_SOURCE = ROOT / "Fathom/Components/MeasurementValueView.swift"
REQUIRED = 4.5

WORLD = re.compile(
    r"static let (\w+) = FathomColorWorld\(\s*"
    r"top: Color\(hex: 0x[0-9A-Fa-f]{6}\),\s*"
    r"middle: Color\(hex: 0x[0-9A-Fa-f]{6}\),\s*"
    r"bottom: Color\(hex: 0x([0-9A-Fa-f]{6})\)"
)
BODY_TEXT = re.compile(r"\.foregroundStyle\(\.white\.opacity\(([01]?\.\d+)\)\)")


def channel(value):
    value /= 255
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def composite(foreground, alpha, background):
    return tuple(alpha * f + (1 - alpha) * b for f, b in zip(foreground, background))


def main():
    worlds = WORLD.findall(DESIGN.read_text())
    if not worlds:
        print(f"error: no colour worlds parsed from {DESIGN}", file=sys.stderr)
        return 2

    alphas = set(BODY_TEXT.findall(TEXT_SOURCE.read_text()))
    if len(alphas) != 1:
        print(
            f"error: expected one body-text alpha in {TEXT_SOURCE.name}, "
            f"found {sorted(alphas) or 'none'}",
            file=sys.stderr,
        )
        return 2
    alpha = float(alphas.pop())

    print(f"body text: white @ {alpha} over each world's bottom stop")
    print(f"required:  {REQUIRED}:1 (AGENTS.md)\n")
    print(f"{'world':<14}{'bottom':<10}{'ratio':>7}  verdict")

    failures = []
    for name, bottom in worlds:
        background = tuple(int(bottom[i : i + 2], 16) for i in (0, 2, 4))
        ratio = contrast(composite((255, 255, 255), alpha, background), background)
        passed = ratio >= REQUIRED
        if not passed:
            failures.append((name, bottom, ratio))
        print(f"{name:<14}#{bottom:<9}{ratio:>6.2f}  {'ok' if passed else 'FAILS'}")

    print(f"\n{len(worlds)} worlds, {len(failures)} failing")
    if failures:
        worst = min(failures, key=lambda f: f[2])
        print(f"worst: {worst[0]} #{worst[1]} at {worst[2]:.2f}:1")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
