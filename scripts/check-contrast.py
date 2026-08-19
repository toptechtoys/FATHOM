#!/usr/bin/env python3
"""Measure body-text contrast against every colour world.

AGENTS.md requires contrast >= 4.5:1 on every surface, and FATHOM-DESIGN.md
names the worst case: "the bottom stop is the worst case, test there."

Body text does not sit on the gradient directly. It sits on FathomSurface's
scrim, laid over the world's bottom stop, so that is what gets measured. Every
input -- the colour worlds, the scrim opacity, the text alpha -- is read from
source rather than restated here, so this cannot drift from what the app
renders. Exits non-zero if any world fails.
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
SCRIM = re.compile(r"static let textScrimOpacity: Double = ([01]?\.\d+)")
CHIP = re.compile(
    r"\.foregroundStyle\(\.black\.opacity\(([01]?\.\d+)\)\)\s*"
    r"\.background\(\.white\.opacity\(([01]?\.\d+)\)\)"
)
MENU_BAR = ROOT / "Fathom/Sections/MenuBar/MenuBarSettingsView.swift"


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
    design = DESIGN.read_text()
    worlds = WORLD.findall(design)
    if not worlds:
        print(f"error: no colour worlds parsed from {DESIGN}", file=sys.stderr)
        return 2

    scrims = SCRIM.findall(design)
    if len(scrims) != 1:
        print(
            f"error: expected one textScrimOpacity in {DESIGN.name}, "
            f"found {scrims or 'none'}",
            file=sys.stderr,
        )
        return 2
    scrim = float(scrims[0])

    alphas = set(BODY_TEXT.findall(TEXT_SOURCE.read_text()))
    if len(alphas) != 1:
        print(
            f"error: expected one body-text alpha in {TEXT_SOURCE.name}, "
            f"found {sorted(alphas) or 'none'}",
            file=sys.stderr,
        )
        return 2
    alpha = float(alphas.pop())

    print(f"body text: white @ {alpha}")
    print(f"surface:   black @ {scrim} over each world's bottom stop")
    print(f"required:  {REQUIRED}:1 (AGENTS.md)\n")
    print(f"{'world':<14}{'bottom':<10}{'bare':>7}{'on scrim':>10}  verdict")

    failures = []
    for name, bottom in worlds:
        world = tuple(int(bottom[i : i + 2], 16) for i in (0, 2, 4))
        bare = contrast(composite((255, 255, 255), alpha, world), world)
        panel = composite((0, 0, 0), scrim, world)
        ratio = contrast(composite((255, 255, 255), alpha, panel), panel)
        passed = ratio >= REQUIRED
        if not passed:
            failures.append((name, bottom, ratio))
        print(
            f"{name:<14}#{bottom:<9}{bare:>6.2f}{ratio:>10.2f}  "
            f"{'ok' if passed else 'FAILS'}"
        )

    # The MenuBar preview chip inverts the treatment: black text on a light
    # surface. It is the one text surface that does not take the scrim, so it
    # is measured separately rather than assumed to be safe.
    chip = CHIP.search(MENU_BAR.read_text())
    if not chip:
        print(
            f"error: could not read the preview chip treatment from "
            f"{MENU_BAR.name}; it may no longer be black-on-light",
            file=sys.stderr,
        )
        return 2
    chip_text, chip_surface = float(chip.group(1)), float(chip.group(2))
    chip_worst, chip_world = min(
        (
            (
                contrast(
                    composite(
                        (0, 0, 0),
                        chip_text,
                        composite(
                            (255, 255, 255),
                            chip_surface,
                            tuple(int(b[i : i + 2], 16) for i in (0, 2, 4)),
                        ),
                    ),
                    composite(
                        (255, 255, 255),
                        chip_surface,
                        tuple(int(b[i : i + 2], 16) for i in (0, 2, 4)),
                    ),
                ),
                n,
            )
            for n, b in worlds
        ),
        key=lambda pair: pair[0],
    )
    chip_ok = chip_worst >= REQUIRED
    print(
        f"\nmenu-bar preview chip: black @ {chip_text} on white @ "
        f"{chip_surface} -- worst world {chip_world} at {chip_worst:.2f}:1  "
        f"{'ok' if chip_ok else 'FAILS'}"
    )

    print(f"\n{len(worlds)} worlds, {len(failures)} failing")
    if failures:
        worst = min(failures, key=lambda f: f[2])
        print(f"worst: {worst[0]} #{worst[1]} at {worst[2]:.2f}:1")
    if failures or not chip_ok:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
