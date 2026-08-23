#!/usr/bin/env python3
"""Measure text contrast against every colour world.

AGENTS.md requires contrast >= 4.5:1 on every surface, and FATHOM-DESIGN.md
names the worst case: "the bottom stop is the worst case, test there."

Text does not sit on the gradient directly. The content column and the rail sit
on FathomSurface's plate, and the Instrument Panel's own materials -- readout
cell, data row, row hover -- layer on top of that plate. Each of those stacks is
composited here and measured separately, because a material that is safe on the
plate is not safe on the field, and the plate is what makes the design's flat
16% cell legal.

Every input -- the colour worlds, the plate, each material, the text alpha -- is
read from source rather than restated here, so this cannot drift from what the
app renders. Exits non-zero if any surface fails on any world.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / "Fathom/Design/FathomDesign.swift"
TEXT_SOURCE = ROOT / "Fathom/Components/MeasurementValueView.swift"
MENU_BAR = ROOT / "Fathom/Components/FathomSurfaces.swift"
BACKGROUND = ROOT / "Fathom/Design/FathomWorldBackground.swift"
FOCUS = ROOT / "Fathom/Design/FathomFocusRing.swift"
GRAIN = ROOT / "Fathom/Design/FathomGrain.swift"
REQUIRED = 4.5

# FathomWorldBackground paints a white radial highlight across the upper field,
# and the plate goes on top of it -- so the ground under text is lighter than
# the world's bottom stop wherever that highlight lands, which is exactly where
# section headers and the first row of readouts sit. Measuring the bottom stop
# alone overstates every result: at a 0.40 plate it read 4.56:1 and the real
# render was 4.18:1. The highlight is read from source and composited first.
HIGHLIGHT = re.compile(r"colors: \[\.white\.opacity\(([01]?\.\d+)\), \.clear\]")

# Semantic colour carries meaning, so it has to be readable wherever it is used
# as text. The tightest of those surfaces is a data row. `live` is excluded by
# name: it is a dot and switch fill, never a word, and non-text graphics are
# held to 3:1 rather than 4.5:1.
SEMANTIC = re.compile(r"static let (\w+) = Color\(hex: 0x([0-9A-Fa-f]{6})\)")
SEMANTIC_BLOCK = re.compile(r"enum FathomSemantic \{(.*?)\n\}", re.S)
GRAPHIC_ONLY = {"live"}
GRAPHIC_REQUIRED = 3.0

# The focus ring is a non-text UI component, so WCAG 1.4.11 asks 3:1 rather
# than 4.5:1. It is measured on the deepest ground it can land on -- the bare
# plate -- because a ring over a readout cell has more to work with.
FOCUS_OPACITY = re.compile(r"static let ringOpacity: Double = ([01]?\.\d+)")

# The grain sits over the field and under the plate, so a bright speckle
# lightens the ground beneath text the same way the highlight does. `overlay`
# drives a bright channel toward white, which is why the noise is clamped
# rather than only faded: at full range and 30% opacity the worst world reads
# 4.15:1. Both the opacity and the ceiling are read from source.
GRAIN_OPACITY = re.compile(r"static let opacity: Double = ([01]?\.\d+)")
GRAIN_CEILING = re.compile(r"static let noiseCeiling: Double = ([01]?\.\d+)")


def overlay(base, blend):
    """CSS `overlay`, per channel, on 0-255 input."""
    unit = base / 255
    result = 2 * unit * blend if unit < 0.5 else 1 - 2 * (1 - unit) * (1 - blend)
    return result * 255

WORLD = re.compile(
    r"static let (\w+) = FathomColorWorld\(\s*"
    r"top: Color\(hex: 0x[0-9A-Fa-f]{6}\),\s*"
    r"middle: Color\(hex: 0x[0-9A-Fa-f]{6}\),\s*"
    r"bottom: Color\(hex: 0x([0-9A-Fa-f]{6})\)"
)
BODY_TEXT = re.compile(r"\.foregroundStyle\(\.white\.opacity\(([01]?\.\d+)\)\)")
CHIP = re.compile(
    r"\.foregroundStyle\(\.black\.opacity\(([01]?\.\d+)\)\)\s*"
    r"\.background\(\.white\.opacity\(([01]?\.\d+)\)\)"
)


def opacity(source, name):
    """Read one `static let <name>: Double = <value>` from FathomSurface."""
    found = re.findall(rf"static let {name}: Double = ([01]?\.\d+)", source)
    if len(found) != 1:
        raise LookupError(
            f"expected one {name} in {DESIGN.name}, found {found or 'none'}"
        )
    return float(found[0])


def assert_darkens(source, accessors):
    """Every surface accessor must tint with black, not white.

    The arithmetic below composites black over the world. A material switched to
    `.white.opacity(...)` would keep the same number and lighten the ground
    instead -- passing this gate while breaking the rule it exists to enforce.
    That is not hypothetical: white 10.5% cards are what the plate replaced, and
    the Instrument Panel design specifies white rows and a lightening hover.
    """
    for name in accessors:
        pattern = rf"static var {name}: Color \{{ \.(\w+)\.opacity"
        found = re.findall(pattern, source)
        if len(found) != 1:
            raise LookupError(
                f"expected one {name} accessor in {DESIGN.name}, "
                f"found {found or 'none'}"
            )
        if found[0] != "black":
            raise LookupError(
                f"{name} tints with .{found[0]}, not .black -- a lightening "
                f"material cannot be measured by this gate and cannot meet "
                f"{REQUIRED}:1 over these worlds"
            )


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


def rgb(hexcode):
    return tuple(int(hexcode[i : i + 2], 16) for i in (0, 2, 4))


def main():
    design = DESIGN.read_text()
    worlds = WORLD.findall(design)
    if not worlds:
        print(f"error: no colour worlds parsed from {DESIGN}", file=sys.stderr)
        return 2

    try:
        plate = opacity(design, "scrimOpacity")
        card = opacity(design, "cardOpacity")
        row = opacity(design, "rowOpacity")
        row_hover = opacity(design, "rowHoverOpacity")
        floor = opacity(design, "minimumTextOpacity")
        assert_darkens(
            design,
            ["contentPlate", "rail", "card", "badge", "row", "rowHover"],
        )
    except LookupError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    grain_source = GRAIN.read_text()
    grain_opacities = GRAIN_OPACITY.findall(grain_source)
    grain_ceilings = GRAIN_CEILING.findall(grain_source)
    if len(grain_opacities) != 1 or len(grain_ceilings) != 1:
        print(
            f"error: expected one opacity and one noiseCeiling in "
            f"{GRAIN.name}, found {grain_opacities} and {grain_ceilings}",
            file=sys.stderr,
        )
        return 2
    grain = float(grain_opacities[0])
    grain_ceiling = float(grain_ceilings[0])

    highlights = HIGHLIGHT.findall(BACKGROUND.read_text())
    if len(highlights) != 1:
        print(
            f"error: expected one white radial highlight in {BACKGROUND.name}, "
            f"found {highlights or 'none'} -- if the background changed, this "
            f"gate no longer knows what is under the plate",
            file=sys.stderr,
        )
        return 2
    highlight = float(highlights[0])

    alphas = set(BODY_TEXT.findall(TEXT_SOURCE.read_text()))
    if len(alphas) != 1:
        print(
            f"error: expected one body-text alpha in {TEXT_SOURCE.name}, "
            f"found {sorted(alphas) or 'none'}",
            file=sys.stderr,
        )
        return 2
    alpha = float(alphas.pop())

    if alpha < floor:
        print(
            f"error: body text is white @ {alpha}, below the "
            f"minimumTextOpacity of {floor} FathomSurface declares",
            file=sys.stderr,
        )
        return 2

    # Each entry is a surface as the app actually stacks it: the plate, then
    # whatever material sits on top of it, then the text.
    #
    # A display title takes full white and is large text, where WCAG would allow
    # 3:1. It is held to 4.5:1 anyway -- AGENTS.md says every surface, and a
    # title that only just clears a weaker bar is not worth the exemption.
    surfaces = [
        ("content plate, title", [], 1.0),
        ("content plate, body", [], alpha),
        ("rail, selected", [], 1.0),
        ("rail, unselected", [], alpha),
        ("readout cell", [card], alpha),
        ("data row", [row], alpha),
        ("data row, hover", [row_hover], alpha),
    ]

    print(f"body text: white @ {alpha} (floor {floor})")
    print(f"grain:     {grain} overlay, noise clamped to {grain_ceiling}")
    print(f"highlight: white @ {highlight} radial, under the plate")
    print(f"plate:     black @ {plate} under the content column and the rail")
    print(f"materials: cell {card}, row {row}, row hover {row_hover} on the plate")
    print(f"required:  {REQUIRED}:1 (AGENTS.md), every surface, every world\n")
    print(f"{'surface':<24}{'worst world':<14}{'bare':>7}{'stacked':>9}  verdict")

    failures = []
    for label, materials, text in surfaces:
        worst = None
        for name, bottom in worlds:
            world = rgb(bottom)
            # brightest speckle the grain can produce, then the highlight, then
            # the plate -- the order the app actually draws them in
            lit_grain = tuple(overlay(c, grain_ceiling) for c in world)
            world = tuple(
                c * (1 - grain) + g * grain for c, g in zip(world, lit_grain)
            )
            ground = composite((255, 255, 255), highlight, world)
            ground = composite((0, 0, 0), plate, ground)
            for material in materials:
                ground = composite((0, 0, 0), material, ground)
            ratio = contrast(composite((255, 255, 255), text, ground), ground)
            lit = composite((255, 255, 255), highlight, world)
            bare = contrast(composite((255, 255, 255), text, lit), lit)
            if worst is None or ratio < worst[0]:
                worst = (ratio, name, bottom, bare)
        ratio, name, bottom, bare = worst
        passed = ratio >= REQUIRED
        if not passed:
            failures.append((label, name, ratio))
        print(
            f"{label:<24}{name:<14}{bare:>6.2f}{ratio:>9.2f}  "
            f"{'ok' if passed else 'FAILS'}"
        )

    block = SEMANTIC_BLOCK.search(design)
    if not block:
        print(
            f"error: could not find FathomSemantic in {DESIGN.name}",
            file=sys.stderr,
        )
        return 2
    semantics = SEMANTIC.findall(block.group(1))
    if not semantics:
        print(f"error: no semantic colours parsed from {DESIGN.name}", file=sys.stderr)
        return 2

    print(f"\n{'semantic':<24}{'value':<10}{'on a data row':>14}  verdict")
    for name, value in semantics:
        required = GRAPHIC_REQUIRED if name in GRAPHIC_ONLY else REQUIRED
        worst = None
        for world_name, bottom in worlds:
            ground = composite((255, 255, 255), highlight, rgb(bottom))
            ground = composite((0, 0, 0), plate, ground)
            ground = composite((0, 0, 0), row, ground)
            ratio = contrast(rgb(value), ground)
            if worst is None or ratio < worst[0]:
                worst = (ratio, world_name)
        ratio, world_name = worst
        passed = ratio >= required
        if not passed:
            failures.append((f"semantic {name}", world_name, ratio))
        note = " (graphic, 3:1)" if name in GRAPHIC_ONLY else ""
        print(
            f"{name:<24}#{value:<9}{ratio:>13.2f}  "
            f"{'ok' if passed else 'FAILS'}{note}"
        )

    # The MenuBar preview chip inverts the treatment: black text on a light
    # surface. It is the one text surface that does not take the plate, so it is
    # measured separately rather than assumed to be safe.
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
                        composite((255, 255, 255), chip_surface, rgb(b)),
                    ),
                    composite((255, 255, 255), chip_surface, rgb(b)),
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

    focus = FOCUS_OPACITY.findall(FOCUS.read_text())
    if len(focus) != 1:
        print(
            f"error: expected one ringOpacity in {FOCUS.name}, "
            f"found {focus or 'none'}",
            file=sys.stderr,
        )
        return 2
    ring = float(focus[0])
    ring_worst = None
    for world_name, bottom in worlds:
        ground = composite((255, 255, 255), highlight, rgb(bottom))
        ground = composite((0, 0, 0), plate, ground)
        ratio = contrast(composite((255, 255, 255), ring, ground), ground)
        if ring_worst is None or ratio < ring_worst[0]:
            ring_worst = (ratio, world_name)
    ring_ratio, ring_world = ring_worst
    ring_ok = ring_ratio >= GRAPHIC_REQUIRED
    if not ring_ok:
        failures.append(("focus ring", ring_world, ring_ratio))
    print(
        f"\nfocus ring: white @ {ring} on the bare plate -- worst world "
        f"{ring_world} at {ring_ratio:.2f}:1  "
        f"{'ok' if ring_ok else 'FAILS'} (graphic, {GRAPHIC_REQUIRED}:1)"
    )

    print(
        f"\n{len(surfaces)} surfaces, {len(semantics)} semantic colours and "
        f"the focus ring x {len(worlds)} worlds, {len(failures)} failing"
    )
    if failures:
        worst = min(failures, key=lambda f: f[2])
        print(f"worst: {worst[0]} on {worst[1]} at {worst[2]:.2f}:1")
    if failures or not chip_ok:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
