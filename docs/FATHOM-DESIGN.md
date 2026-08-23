# FATHOM — Design System

**Status: LOCKED, v2.0 · 23 August 2026 — Instrument Panel**
Visual spec: `fathom-app.html`. Open it. It is normative — where this document
and the prototype disagree, the prototype wins.

v2.0 replaced the poster direction with the Instrument Panel on 23 August: one
always-on window, every section a set of live readouts behind a 64px icon rail.
No poster, no Scan button, no result state.

Locked means the argument is over. Implement it. Changes go through the
prototype first, then this document, then Swift. Not the other way round.

**Swift has the foundation and none of the vocabulary.** The colour worlds, the
plate, the materials and the semantic palette are implemented and gated. The
rail, the readout grid, the thirteen panel types and the sparklines are not.

---

## The idea in one line

The window is an instrument panel. It is always live, every section is a set of
readouts, and there is nothing to start.

The calibration reference was CleanMyMac. Two things were taken from it and one
was deliberately rejected.

**Taken.** Colour fills the entire window, rail included, so the app reads as one
lit object rather than chrome wrapped around a content pane. And the colour tells
you where you are before you read a word.

**Rejected.** Its Assistant screen reports "Mac Health: Good", a score with no
published formula. FATHOM's Home shows the real free number, the four things
worth looking at, and the sentence *nothing is wrong*. No score, ever.

This replaced an earlier direction in which each screen was a poster — a
rendered object, a title, one sentence and a Scan button — that filled with data
only after a pass. The poster was honest but it made the app feel like a tool
you operate. The panel is a tool you read. Every trace of the poster is gone:
no object, no Scan button, no empty landing state, no result screen.

---

## One shell

There are no archetypes any more. Every one of the twenty sections is the same
shell, and differs only in its readouts.

**The field.** Each section owns a three-stop colour world,
`linear-gradient(177deg, b1 0%, b2 60%, b3 100%)`, carried by the whole window
including the rail. Over it: a four-octave value-noise grain at 30% with
`overlay` blend, tiled at 180pt, and a white radial highlight across the upper
field. The plate goes on top of both.

**The grain's noise is bounded, not just faded.** `overlay` drives a bright
channel toward white, and the grain sits *under* the plate, so a bright speckle
lightens the ground beneath text exactly as the highlight does. Unbounded noise
at 30% takes the worst world to 4.15:1 and fails the rule outright. Clamping the
noise to 0.40–0.60 around mid-grey keeps the designed opacity and blend and
makes the worst speckle 4.60:1. That is narrower than raw `feTurbulence`, but
only at the tails — four-octave fractal noise already spends most of its time
near the middle, and what the clamp removes is the rare speckle nobody wanted.

The texture is generated from a fixed seed and tiles seamlessly, so two
screenshots of the same screen are identical. Both its opacity and its ceiling
are read from source by `check-contrast.py`, which composites the brightest
speckle the band permits.

**The rail.** 64px, always an icon rail, never labelled. See *The rail*.

**The status strip.** 32px, `rgba(0,0,0,.25)`, 10px/700/.1em uppercase —
`INSTRUMENT PANEL` left, `1 HZ · LIVE` right.

**The section header.** Baseline-aligned: title, then the machine line
(*MacBook Air M2 · 16 GB · 142 days recorded*), then a live pill on the right
carrying a pulsing dot and the section's own subtitle. `.5px` bottom hairline,
20px below it.

**The readouts.** Three or four cells across the top of every section, in a grid
of `repeat(auto-fit, minmax(190px, 1fr))`, 1px apart, each drawing its own
hairline — *the gap is the rule*. No radius, no lift, no shadow. Hover deepens
the cell.

**The panels.** Everything below the readouts. No card, no blur: a `.5px` top
hairline, a tracked label, and the content.

A section with nothing to show yet says so in a note and offers the one action
that would fill it. It does not show a poster and it does not show zeros.

---

## Colour worlds

Each section owns a three-stop field. Dark at the top, saturated at the bottom.
The whole window carries it, rail included — the rail is a translucent panel
floating *over* the field, never a separate dark slab.

| Section | Top | Mid | Bottom |
|---|---|---|---|
| Menu Bar | `#062737` | `#0C6076` | `#1FA3B8` |
| Home | `#08133A` | `#1B3E86` | `#3F79CE` |
| Deep Scan | `#1B0E42` | `#4E23A0` | `#8B5CF6` |
| CPU | `#04203A` | `#0B5296` | `#2E8BE0` |
| GPU | `#2A0838` | `#6D1580` | `#B040C8` |
| Memory | `#12063A` | `#3B1D9E` | `#6F4BE0` |
| Sensors & Power | `#3A1206` | `#96380A` | `#DE7A17` |
| Network | `#03302C` | `#0A7A72` | `#2CB9AC` |
| Bluetooth | `#062B1E` | `#0D7A4E` | `#2CBE7C` |
| Storage | `#04263A` | `#0C6B90` | `#2BB6D4` |
| Timeline | `#26063E` | `#6B1AA0` | `#B23FD4` |
| Explore | `#0C1445` | `#243397` | `#5566DC` |
| Reclaim | `#032A1F` | `#0A7150` | `#26B87C` |
| Endurance | `#051E2C` | `#0F5A72` | `#33A2B4` |
| Attribution | `#101334` | `#333A80` | `#6B74CE` |
| Weekly digest | `#28211A` | `#6F5936` | `#BE9A56` |
| Applications | `#141046` | `#3A2AA8` | `#7059E8` |
| Cloud | `#07234A` | `#12559E` | `#3691E0` |
| Maintenance | `#331A05` | `#8A4A0B` | `#D08A1D` |
| SSD Health | `#0A1F2E` | `#1D5570` | `#4A93AE` |

Transition on navigation: 550 ms, `cubic-bezier(.16,1,.3,1)`. The whole field
cross-fades at once; nothing else moves with it.

### Semantic colour

Used only for meaning, never decoration.

| Token | Value | Means |
|---|---|---|
| Freeable | `#8DF3C4` | This space actually comes back |
| Caution | `#FCD98A` | Real but conditional — needs care |
| Blocked | `#FFCACA` | Frees nothing, or a genuine risk |
| Informational | `#BFD9FF` | Worth knowing, no action |
| Live | `#5CE6A8` | Sampling right now — dots and switches only |

Red never appears for routine state. A full disk is not an emergency.

Blocked and informational were `#FFAFAF` and `#A9CBFF`. As text on a data row
they measured 3.88:1 and 4.10:1, so both were lightened until they clear the
rule with the margin the rest of the system keeps — 4.71:1 and 4.72:1. The hue
is unchanged; these are the same four meanings, made legible on the surface they
actually land on.

**Live is not a text colour.** `#5CE6A8` reads 4.32:1 on a row, which is fine
for the pulsing dot and the switch fill it is used for — non-text graphics need
3:1 — and not fine for a word. If it ever needs to carry text, it needs
lightening first.

---

## Panels

Thirteen panel types carry every section. Each is built once and takes data.
All thirteen are built and in use.

Two departures from the prototype turned up during implementation and are
recorded rather than quietly absorbed. **Rule rows** are per-recipe dry runs,
not a multi-select list that recomputes a running total — Reclaim prepares and
reviews one recipe at a time, because that is the granularity at which a cost
can be stated honestly. And **Explore keeps a tree** rather than a flat
two-number table: its expand-and-collapse hierarchy carries information the
table cannot.

| Type | Used by | What it is |
|---|---|---|
| Sparkline | CPU, GPU, Memory, Network, Sensors | 60 samples at 1 Hz. `viewBox 0 0 1000 56`, 52px tall, 2.5px stroke, area fill at 13% |
| Core bars | CPU | Eight vertical bars from a baseline. Performance cores at 92% white, efficiency at 50%. Height animates 600ms |
| Two-number table | Deep Scan, Explore, SSD Health | Item / on disk / freed if deleted. Zero-recovery rows read `0 GB`; freeable values take the freeable colour |
| Segment bar | Memory, Cloud | Stacked proportional bar with a legend naming every segment, *unaccounted* included |
| Treemap | Storage | Area is size on disk. Every rectangle names its own two numbers |
| Day columns | Timeline | Seven columns, growth up and deletion down from a shared baseline, net under each |
| Device rows | Bluetooth, Applications, Cloud | Name / meter / value. A device that publishes no battery reads *does not report* |
| Rule rows | Reclaim | One row per validated recipe: what it frees, what it costs, and a dry run |
| Feed | Home | Four *worth a look* items, from `FindingEngine`. Empty is a valid, expected state |
| Grid | Home | Every section, one number each, each a link to the screen that produced it |
| Chain | Endurance | The arithmetic, left to right, with the conclusion at the end |
| Menu-bar preview | Menu Bar | The widget at actual size, 26px tall |
| Digest card | Weekly digest | A light card on the dark field, closing on *Nothing needs you. This is the whole message.* |

Every section also ends in a **note**: a 19px display headline and a sentence of
body capped at 66 characters, saying the thing the numbers cannot.

### What counts as worth a look

The feed is the one panel that decides what to say rather than being handed it,
so the deciding lives in `FindingEngine` in FathomKit, with tests.

Every finding traces to a measured value. What the engine adds is a *threshold*,
which is a judgement about what deserves attention rather than a measurement —
so the thresholds are named constants with their reasoning attached, not magic
numbers buried in a condition. A threshold is the one place this product could
quietly become a nag.

Four rules govern it. **An empty feed is the expected result on a healthy Mac**,
and renders no panel at all rather than an empty one headed *worth a look* —
rule 7 forbids manufacturing urgency, and padding the list to look busy is
exactly that. **A partial scan outranks everything**, because knowing the totals
are incomplete changes how every other number reads. **Nothing unmeasured
becomes a finding**: an unpublished value produces silence, never a zero.
And **a figure that frees nothing is white, not red** — zero is a fact there,
not a fault.

**Three states in every one of them.** Known, not published, not attributable.
A panel that cannot render all three is not finished. The prototype's data is
all known values, so it demonstrates the shape and not the states — the states
are in `AGENTS.md` and they are the product.

---

## Type

| Role | Family | Size | Tracking |
|---|---|---|---|
| Section title | Archivo SemiExpanded 600 | `clamp(28px, 2.8vw, 40px)` | −0.028em |
| Readout value | Archivo SemiExpanded 600 | `clamp(30px, 2.7vw, 38px)` | −0.03em |
| Readout unit | Archivo | 13px | −0.008em |
| Note headline | Archivo SemiExpanded 600 | 19px | −0.022em |
| Machine line, note body | Archivo | 12.5px | −0.008em |
| Live pill, readout note, hint | Archivo | 11.5px | −0.008em |
| Row | Archivo | 13px | −0.008em |
| Row annotation | Archivo | 10.5px | −0.008em |
| Micro-label | Archivo 600 | 9px, uppercase | 0.16em |
| Status strip | Archivo 700 | 10px, uppercase | 0.1em |
| Path, identifier | JetBrains Mono | 11–12px | 0 |

Readout notes cap at 32 characters, body copy at 66. Titles use
`text-wrap: balance`.

**Every numeral in a column that can be compared is tabular.** Non-negotiable —
`font-variant-numeric: tabular-nums` is set globally, not per component.

**Archivo, adopted 23 August.** One family for display, UI and numerals, with
JetBrains Mono for paths. Bricolage Grotesque and Instrument Sans belonged to
the poster direction and are gone from the bundle.

Five static instances ship: Regular, Medium, SemiBold and Bold at normal width,
and SemiExpanded SemiBold for titles and readout values. Attribution and the SIL
Open Font License are in `THIRD_PARTY_NOTICES.md`.

**`wdth 104` is not reachable and the UI face is 100.** The handoff specifies
`wdth 112` for display and `104` for UI, which are variable-font axis values.
Archivo ships as static instances at width classes 62, 75, 87.5, 100, 112.5 and
125. SemiExpanded measures 112.5% against the specified 112 — close enough to be
the same face — but nothing sits at 104, so the UI takes normal width at 100.
The alternative was SemiExpanded at 112.5, which is more than twice as far from
the specification in the other direction. Closing that four-unit gap needs the
variable font, which is a separate decision about bundling a second file.

---

## Materials

One plate, and everything else layered on it. The full derivation, the measured
contrast of every surface and the reason the materials darken rather than
lighten are in **The plate, and why the materials are dark** below.

| Surface | Value | Over |
|---|---|---|
| Plate — content column and rail | `rgba(0,0,0,.45)` | the field |
| Readout cell, card, tile | `rgba(0,0,0,.16)` | the plate |
| Data row | `rgba(0,0,0,.07)` | the plate |
| Data row, hover | `rgba(0,0,0,.13)` | the plate |
| Status strip | `rgba(0,0,0,.25)` | the plate |
| Grid hairline | `.5px rgba(255,255,255,.14)` ring per cell | the cell |
| Panel divider | `.5px rgba(255,255,255,.16)` | — |
| Rail edge | `.5px rgba(255,255,255,.09)` | — |
| Active rail item | `linear-gradient(180deg, rgba(255,255,255,.26), rgba(255,255,255,.13))` | the rail |

Radii: 15 window · 14 digest card · 12 row · 10 rail item · 8 focus ring ·
**0 for readout cells and panels**. The square cell is the instrument-panel
departure from the old card radii, and it is deliberate: a readout is not a card.

**The grid hairline is drawn by the cells, not behind them.** Each readout cell
carries its own `.5px` ring and the cells sit 1px apart, so two rings meet to
make the line. The obvious construction — a hairline-coloured container showing
through the gap — breaks on the last row: when the cell count does not fill the
row, the leftover track shows as a pale block. Rings leave it as plate.

The rail keeps `backdrop-filter: blur(46px) saturate(135%)`. Nothing else blurs.
The old white-tinted tiles and the detail panel are gone.

---

## Actions

A section that can do something ends with one pill: `rgba(255,255,255,.14)`,
`.5px` white border at 22%, `inset 0 1px 0 rgba(255,255,255,.20)`, 15px radius,
13px semibold. Hover `scale(1.04)`, press `scale(0.96)`, 160ms.

One per section, never two. The circular Scan button is gone with the poster —
there is nothing to start.

**The label states the outcome and the cost, in that order.** *Move 101.0 GB to
Trash.* *Reclaim 132.6 GB.* *Evict 61.2 GB.* Never *Continue*, never *Optimise*,
never a verb with no object.

---

## The rail

64px, fixed, never expands. Twenty items in four groups, divided by a 22×1px
hairline rather than a text heading:

| Group | Sections |
|---|---|
| — | Menu Bar, Weekly digest |
| Overview | Home, Deep Scan |
| System | CPU, GPU, Memory, Sensors & Power, Network, Bluetooth |
| Storage | Storage, Timeline, Explore, Reclaim, Endurance, Attribution, Applications, Cloud, Maintenance, SSD Health |

Items are 42×42 at 10px radius, carrying a 19px icon mask so the glyph inherits
its colour. Twenty custom stroke icons, 20×20 viewBox, 1.65 stroke, round caps
and joins. Inactive icons take the same 82% white as body text; the active item
gets the gradient fill and a white icon. Every item carries its section name as
a tooltip and as its accessible label.

Traffic lights sit above: three 9px circles, 6px apart, 16px of padding below.

The footer is a single 7px `#5CE6A8` dot with a 9px glow, pulsing 2.2s, whose
tooltip carries the app's own idle cost — `0.2% CPU · energy 2.1`. Showing your
own cost in your own chrome is a claim only an honest utility can make.

The public IP row moved into the Network section. The rail has no room for it
and no business holding it.

---

## Responsive

Fluid by default. `clamp()` on type, `auto-fit` / `minmax()` on every grid so
readouts and rows reflow without breakpoints.

**There is no 1080px breakpoint any more.** The rail is an icon rail at every
width, so the old sidebar collapse has nothing left to do.

**≤ 760px.** Content padding tightens to `18px 16px 32px`. Tables and device
rows drop to two columns, and the row annotation moves inline beside its value
instead of below it.

Verified with no horizontal overflow at 1520, 1200, 1000, 820 and 720px.

Minimum window: 720 × 560.

---

## Motion

| Event | Duration | Curve |
|---|---|---|
| Section enter | 450 ms, `translateY(12px)` and fade | `cubic-bezier(.16,1,.3,1)` |
| Colour world change | 550 ms | same |
| Core bar height | 600 ms | same |
| Rail item hover | 220 ms | same |
| Cell and row hover | 200–250 ms | same |
| Press feedback | 160–180 ms | same |
| Live dot pulse | 2.2 s loop | ease-in-out |

The 7.5s object breathe is gone, along with the object it belonged to.

Under Reduce Motion: the section enter, the live pulse and the colour transition
all stop. Press and hover feedback remain — they confirm an action, which is
meaning, not decoration.

**Nothing animates on the 1 Hz tick except the core bars.** Sparklines redraw
without transition and the readouts simply change. A number that eases into
place is a number you cannot read.

---

## Writing

Sentences, not fragments. No exclamation marks. No emoji. Never "junk",
"optimise", "boost", "clean up your Mac".

Name the limit in the same breath as the number. *"0.9 GB we cannot attribute."*
*"This gets better every day it runs."* *"The keyboard will not say."*

The five sentences that define the voice, all live in the prototype:

> This Mac has no battery.

> Three days are empty because FATHOM was not installed yet.

> That last row is the honest one.

> Your SSD is fine, and most of what you have read about Apple silicon SSD wear
> is wrong.

> Nothing needs you. This is the whole message.

---

## Accessibility

Contrast ≥ 4.5:1 for **every** text surface on **every** one of the twenty
worlds — not body text on the worst field, which is the narrower claim this
document used to make and the reason section titles shipped at 2.40:1 unnoticed.
`scripts/check-contrast.py` composites all seven surfaces and runs in CI. What
counts as a surface is in *The plate* below.

Never colour alone: freeable green always carries the word or the number too.

Full keyboard navigation. Arrow keys move between sections in all four
directions, wrapping at both ends and ignoring modified presses, so the rail is
reachable without the pointer.

**The focus ring is 2px white at 60%, 3px offset, 8px radius** — drawn, not
inherited. `FathomFocusRing` applies it to the rail items, action pills,
actionable rows and the Home grid: everything focusable that sits on a colour
world. Controls inside a sheet or popover keep the system ring, because those
are standard macOS chrome and the system ring belongs there.

This was an open divergence, and the objection to closing it was real: the
system ring honours the user's accessibility settings, and replacing it can
regress the very users the requirement exists for. That objection is about
*losing the settings*, not about the ring's appearance, so the ring honours
them. **Under Increased Contrast it goes to full white at 3px**, which is
stronger than the system ring it replaces rather than weaker.

60% was checked rather than assumed. A focus ring is a non-text UI component,
so WCAG 1.4.11 asks 3:1 rather than 4.5:1, and 60% white measures 3.31:1 on the
worst world's plate — clear, though not by much, which is why the gate reads the
value from `FathomFocus.ringOpacity` and fails the build if it is weakened.

VoiceOver labels state value *and* provenance: *"Freed if deleted, 0 gigabytes,
sparse file."* Sparklines, core bars and segment bars carry meaning no label
currently states, and each needs one before it ships.

**Dynamic Type.** Every font helper passes `relativeTo:`, so the whole scale
grows — including the 9px tracked micro-labels, which are the case that worried
us. The risk was never the type, it was the containers: a fixed height around
text clips it, and a fixed height around a chart *and* its label lets the label
eat the chart.

Chart dimensions are therefore `@ScaledMetric`, not constants. A reader who
enlarged the text wants a bigger chart, not a bigger caption over the same 52pt
of line. The sparkline, core bars, segment bar, day columns and treemap all
grow with the text size.

The treemap grows as a whole rather than per tile. Tile areas are proportional
to bytes, so a label growing its own tile would make the picture lie.

**The menu-bar preview is capped, on purpose.** macOS gives the widget 22 points
whatever the user's text size, so a preview that grew would misrepresent the one
thing that panel exists to show. It holds at Large and the caption beside it
says why.

What is still unproven is how it looks: whether the enlarged charts read well
and whether the tracked micro-labels stay legible at Accessibility sizes. That
needs the app on a real display.

### The plate, and why the materials are dark

Body text is white at 82%. Directly on the fields that lands between 2.05:1
(Bluetooth) and 4.32:1 (Memory) — every one of the twenty short of the rule
above. The cards used to be white at 10.5%, which made it worse: tinting a card
white lightens the very field the text is trying to contrast against.

The fix is **one plate, not a plate per element**. Everything that carries text
— the whole content column, and the rail beside it — sits on a **black plate at
45%**. The Instrument Panel's own materials then layer on top of that plate at
exactly the values the design specifies: the readout cell is still 16%, the data
row still 7%, its hover still 13%. Their *relative* flatness, which is the point
of that direction, is preserved. What changed is the ground underneath them.

The twenty colour worlds are untouched.

Every figure below composites the white 15% radial highlight
`FathomWorldBackground` paints across the upper field, because the plate sits on
top of that highlight and the ground under text is lighter than the world's
bottom stop wherever it lands.

| Surface | Stack | Worst world (Bluetooth) |
|---|---|---|
| Content plate — display title, full white | `.45` | 6.12:1 |
| Content plate — body text at 82% | `.45` | 4.72:1 |
| Rail — selected, full white | `.45` | 6.12:1 |
| Rail — unselected at 82% | `.45` | 4.72:1 |
| Readout cell, card, tile | `.45` + `.16` | 5.87:1 |
| Data row | `.45` + `.07` | 5.19:1 |
| Data row, hover | `.45` + `.13` | 5.63:1 |

**Why 45% and not 40%.** 40% is what the bottom stop alone appears to allow, and
it is wrong: under the highlight the same surface renders 4.18:1. The minimum
that survives the highlight is 44%, and 45% is that with a little room. Measuring
the gradient without the highlight overstates every result on this screen, which
is why the gate now reads the highlight from source too.

**The materials are black where the design draws them white.** This is the one
place the Instrument Panel direction is not followed literally, and it is
deliberate. On a plate, a white tint lightens back toward the field the plate
exists to escape — the design's white 7% row measures 1.96:1 and its lightening
13% hover 3.60:1, both short of the rule. The magnitudes the design chose are
kept exactly; only the sign is flipped. Which is the same conclusion the next
paragraph reached the first time.

**Hover deepens, it never lightens.** On a dark ground a lighter hover walks the
contrast back toward the field, which is how the first draft of this change
broke the rule it was written to satisfy.

**Text never goes below 82% white.** The bare plate is what forces this: 82% is
its minimum, so any text that might sit directly on the plate has to clear that
bar. The deeper surfaces would permit a quieter tier — the cell tolerates 69% and
a row 76% — but a second tier is a rule about *where* a colour may be used, and
that is not a rule a gate can enforce per element. One tier is enforceable, so
hierarchy comes from size, weight and tracking instead of opacity. Every note and
micro-label reads at 82%, the same as body text.
`FathomSurface.minimumTextOpacity` states this, and the gate fails the build if
`MeasurementValueView` drops below it.

**Adding a colour world.** The plate leaves the tightest surface — body text at
82% — with 0.22 of margin. A world with a brighter bottom stop than Bluetooth's
`#2CBE7C` will fail the gate. Check before adding one.

`HardwareResultCard` layers `.ultraThinMaterial.opacity(0.15)` behind its
material, which lightens the composite by an amount the gate does not model. The
cell's 1.20 of margin absorbs it, but the rendered result still wants a look on
the reference machine.

`scripts/check-contrast.py` reads the worlds, the grain, the highlight, the
plate, every material, the semantic palette, the focus ring and the text alpha
from source, composites each stack above, and fails if any of the seven
surfaces drops below 4.5:1 on any of the twenty worlds. It also refuses a
material that tints with white rather than black, because a lightening material
would keep its number and quietly break the rule. It runs in CI.

---

## What is deliberately absent

No health score, letter grade or overall percentage. No red badge for routine
state. No countdown or predicted failure date. No confetti, no celebration on
completion — you reclaimed disk space, you did not win anything. No dark pattern
in the upgrade path. No "recommended" preselected destructive action.

An earlier draft of Endurance displayed *"March 2030 ±14 months"*. Apple does
not publish a TBW rating for this drive; that number was invented, by us, in a
product built to oppose exactly that. It now reads *decades, not years*, with
the arithmetic shown. Keep it that way.
