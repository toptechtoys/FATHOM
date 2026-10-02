# Design and accessibility notes

Read before you change a screen, a colour world, a material, the field behind
the plate, or the contrast gate. `AGENTS.md` keeps the rules that always apply:
the prototype is the visual spec, and where it and the contrast rule disagree
the rule wins and you record it. This note holds the detail behind them.

## The native-feel rider

*Rider, 25 August 2026.* The owner reviewed the running app on screen and
directed a native-feel pass that supersedes the prototype on five points —
type renders ×1.32, the icon rail is a 214pt labelled sidebar, readout cells
are separated cards, the prominent action is a filled button, and scanning
screens carry an elapsed clock. Each is recorded with its values in
`FATHOM-DESIGN.md` §*The native-feel pass*. The colour worlds, materials,
grain, highlight and everything else still follow the prototype, and the
prototype was regenerated on 25 August to fold these in, so it and the app
agree again.

## Where the prototype and the contrast rule have disagreed

Detail for *Where the prototype and the contrast rule disagree, the rule wins* in
`AGENTS.md`.

This has happened four times: the design's white materials — one flip, which
took the readout cell, the data row and its hover from white tint to black — two
semantic colours, the grain's blend, and the white highlight over the field,
which the app draws at half the prototype's strength because 30% puts body text
at 4.24:1. Each is documented in `FATHOM-DESIGN.md` with the measurement that
forced it.

## When the field and the prototype disagree for no reason

Continues the rule above.

**And where they disagree for no reason, that is a defect.** The field was the
last thing still carrying values from the direction the Instrument Panel
replaced, because it was written before the prototype was and nobody re-read it
afterwards: its gradient put the middle stop at 50% against the specified 60%,
it painted a fourth layer under the plate that the prototype has no equivalent
for, and it drew the grain over the highlight rather than under it. None of that
failed a build, and none of it was visible to inspection — which is why
`check-contrast.py` now reads the field's layers and their order out of
`FathomWorldBackground` and refuses to run if they are not what it composites.

## The contrast gate

Contrast is gated rather than reviewed. `scripts/check-contrast.py` composites
the whole stack from source — worlds, grain, highlight, plate, materials,
semantic palette, focus ring, text alpha — and fails the build if any surface
drops below the rule on any of the twenty worlds. **Anything you draw beneath
the plate must be added to it.** Three separate layers have now quietly cost
text contrast, and none was visible to inspection.

## Labels

Labels live in the shared components rather than the section views, so a label
written beside the value it describes cannot drift from it — and a wrong one is
wrong everywhere at once. A static per-view audit of labels, charts, motion
gating and type scaling was done on 25 August and fixed what it found;
VoiceOver itself has still never spoken this interface, which stays a
reference-machine task in `RELEASE-GATES.md`.
