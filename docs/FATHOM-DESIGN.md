# FATHOM — Design System

**Status: LOCKED, v2.1 · 25 August 2026 — Instrument Panel, native-feel pass**
Visual spec: `fathom-app.html`. Open it. It is normative — where this document
and the prototype disagree, the prototype wins.

v2.0 replaced the poster direction with the Instrument Panel on 23 August: one
always-on window, every section a set of live readouts, behind a 64px icon rail
at the time. No poster, no Scan button, no result state. v2.1 is the owner's
native-feel pass of 25 August, which turned that rail into a 214pt labelled
sidebar and the readouts and panels into cards; see *The native-feel pass*.

Locked means the argument is over. Implement it. Changes go through the
prototype first, then this document, then Swift. Not the other way round.

**Swift implements all of this.** The colour worlds, plate, grain, materials,
semantic palette and focus ring are gated by `scripts/check-contrast.py`; the
rail, readout grid and all thirteen panel types are built, and every one of the
twenty sections uses them.

Audited value by value against the prototype: colour worlds, materials, grain,
highlight, spacings, tracking and the focus ring all match. The divergences are
recorded in *Type* (the ×1.32 scale) and *The native-feel pass* (the sidebar,
the readout and panel cards, the filled action button), and in *Motion* — the
section enter rides the 550 ms colour-world curve rather than a 450 ms curve of
its own.

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
including the rail. Over it, in this order: a four-octave value-noise grain at
30% with `overlay` blend, tiled at 180pt, then a white radial highlight across
the upper field. The plate goes on top of all three.

**The order is part of the specification, not an implementation detail.** The
grain blends with `overlay`, which does not commute with the highlight's alpha
compositing — grain-then-highlight and highlight-then-grain produce different
grounds under the same text. `check-contrast.py` composites the three in the
order above and refuses to run if `FathomWorldBackground` draws them in any
other order, or draws a fourth layer it has not been told about.

Two departures from the prototype, both below: the highlight is drawn at half
strength, and the 3° tilt is not reproduced. SwiftUI's gradient endpoints are
fractions of the view rather than an angle, so a fixed pair of them holds an
aspect ratio and the tilt would swing with every window resize.

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

**The rail.** Was 64px, icons only; a 214pt labelled sidebar since 25 August
2026. See *The rail*.

**The status strip.** 32px, `rgba(0,0,0,.25)`, 10px/700/.1em uppercase —
`INSTRUMENT PANEL` left, `1 HZ · LIVE` right.

**The section header.** Baseline-aligned: title, then the machine line
(*MacBook Air M2 · 16 GB · 142 days recorded*), then a live pill on the right
carrying a pulsing dot and the section's own subtitle. `.5px` bottom hairline,
20px below it.

**The readouts.** Three or four cards across the top of every section, laid out
auto-fit at `minmax(210pt, 1fr)` with a 10pt gap. Each is radius 12 over the 16%
cell material, with a top-lit gradient border (white 20% fading to 5%, 1pt) and
a soft shadow (black 22%, radius 8, y 2). Hover deepens the card.

**The panels.** Everything below the readouts. A radius-12 card at the data
row's 7%, with the same top-lit border at lower strength (white 14% to 4%) and a
lighter shadow (black 18%, radius 8, y 2), a tracked label, and the content.

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
| Core bars | CPU | One vertical bar per logical core, from a baseline — twelve on the reference M4 Pro. Performance cores at 92% white, efficiency at 50%. Height animates 600ms |
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

**The prototype sizes display type fluidly and Swift does not.** The prototype
draws section titles at `clamp(28px, 2.8vw, 40px)` and readout values at
`clamp(30px, 2.7vw, 38px)`; Swift uses fixed 34pt and 34pt, which is what those
clamps resolve to at roughly 1200pt of window width.

This is a deliberate divergence, recorded rather than left to be discovered.
Viewport-driven type is a web idiom. On macOS the platform convention is Dynamic
Type, which Swift honours through `relativeTo:` — and the two fight each other:
a reader at Accessibility Large in a narrow window would have their type scaled
down by the viewport and up by their own setting, ending somewhere neither asked
for. Type here answers to the user's text size, not to how wide they dragged the
window.

Everything else in this table matches the prototype exactly, and so do the
spacings, tracking, materials, and the hover, press and core-bar durations. The
scale factor and the native-feel pass are the divergences, both recorded below.

**The whole scale renders ×1.32 as of 25 August 2026.** The owner watched the
app run on a real display and called the table above too small — twice: a
first pass at ×1.2 was reviewed on screen and still read small, and ×1.32 is
the second review's ask. Every size in this document and the prototype is
still the *stated* size; `FathomType.scale` in `FathomDesign.swift` multiplies
them at render time so the scale moves as one number. When the factor
settles, it gets baked into these tables and the prototype as the recorded
sizes.

---

## The native-feel pass, 25 August 2026

The owner reviewed the running app and directed it: *"it looks like a
website, not a proper app — colors stay, text bigger, real buttons, like
CleanMyMac."* The colour worlds, materials, grain and highlight are untouched.
What changed, each an owner decision reviewed on screen:

- **Type renders ×1.32** — see *Type* above.
- **The icon rail became a 214pt labelled sidebar** — see *The rail* below.
- **Readout cells became cards.** The 1px shared-hairline grid became a 10pt
  gap; each card is radius 12 with its own border — a top-lit gradient
  stroke, white 20% fading to 5% — and a soft shadow (black 22%, radius 8,
  y 2). Cell minimum width 190 → 210 for the larger type. The cell's 16%
  material and every text-bearing surface are unchanged, so the contrast
  gate's model still holds; the border and shadow carry no text.
- **The prominent action is a filled button**: black 82% text on white 88%
  fill, radius 12 — the same pairing the menu-bar preview chip already
  passes the gate with, at 12.04:1 worst-world. Hover lifts the fill to
  100%. Secondary actions keep the translucent style.
- **Scanning screens carry a live elapsed clock** ("Running for …"), because
  a volume walk can print nothing for half an hour and a screen with no
  moving number reads as hung.
- **Panels are cards too** (second review, same day): the bare
  hairline-and-label division became a radius-12 card at the data row's 7%,
  with the same top-lit border treatment as the readout cards at lower
  strength, so readouts keep the heavier weight. Darkening the ground under
  82% text only raises contrast, so the gate's plate model stays the floor.
- **Empty and scanning sections centre their message block** in the leftover
  viewport height instead of stacking it under the header with a page of
  dead ground below.

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
| Readout card border | 1pt `linear-gradient(180deg, rgba(255,255,255,.20), rgba(255,255,255,.05))` | the card |
| Panel card border | 1pt `linear-gradient(180deg, rgba(255,255,255,.14), rgba(255,255,255,.04))` | the card |
| Panel divider | `.5px rgba(255,255,255,.16)` | — |
| Rail edge | `.5px rgba(255,255,255,.09)` | — |
| Active rail item | `linear-gradient(180deg, rgba(255,255,255,.26), rgba(255,255,255,.13))` | the rail |

Radii: 15 window · 14 digest card · 12 readout card · 12 panel card ·
12 action button · 12 row · 8 rail item · 8 focus ring. The square,
hairline-separated cell belonged to the pre-native-feel Instrument Panel and is
gone: the cells sit 10pt apart now and each owns its whole border, so a readout
is a card again.

The rail keeps `backdrop-filter: blur(46px) saturate(135%)`. The only other blur
in the app is Reclaim's journal-recovery banner, which draws
`.ultraThinMaterial` under its own text in all three of its states; the contrast
gate cannot model either, so both are reference-machine readings. The old
white-tinted tiles and the detail panel are gone.

---

## Actions

A section that can do something ends with one button, 13px semibold, radius 12.
**Prominent**: black 82% text on a white 88% fill, 100% on hover, no border,
shadow black 28% at radius 9, y 3. **Secondary**: white 92% text on a white 8%
fill, 14% on hover, `.5px` white border at 22%, no shadow. Hover `scale(1.02)`,
170ms; there is no press transform.

**One primary action per section.** A secondary control that declines or
retreats — *Back*, *Scan again*, *Cancel* — is not a second action and does not
count against this; it is the way out of the first one. Storage, Deep Scan and
Cloud each carry one, and each needs it.

This read "one per section, never two" until 26 August, and those three sections
had always contradicted it. The rule was what was wrong, not the sections:
removing a reader's way out of a dry run to satisfy a sentence would have been
the worse reading of it. Two *primary* actions side by side remains forbidden —
that is a section that has not decided what it is asking for.

The circular Scan button is gone with the poster — there is nothing to start.

**The label states the outcome and the cost, in that order.** *Move 101.0 GB to
Trash.* *Reclaim 132.6 GB.* *Evict 61.2 GB.* Never *Continue*, never *Optimise*,
never a verb with no object.

---

## The rail

**Superseded 25 August 2026: the rail is now a 214pt labelled sidebar.** The
prototype's rule was "always icons, never labels"; the owner reviewed the
running app and asked for names beside the icons, CleanMyMac-style. Each row
is icon + section name at 12px (×1.32) in a 34pt row, radius 8, full-width
selection chrome, in a sidebar 214pt wide; the groups, icons, colours, tooltips
and accessible labels are unchanged, and the footer now shows the live pill and
the widget's own measured cost as visible text rather than a tooltip.

The prototype was regenerated on 25 August and now draws the 214px sidebar too,
so the paragraphs below are the historical record of the icon rail, not a live
specification — nothing draws them any more. The group table, the icon
construction and the traffic-light reservation still hold.

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

The footer carries a single 7px `#5CE6A8` dot with a 9px glow, pulsing 2.2s,
beside the words *Live · 1 Hz* and the widget's own **measured** CPU figure as
visible text; the full sentence — item count and, before the widget has
measured itself, the fact that it has not — is in the tooltip and the accessible
label. It is never the 0.2% budget: the prototype's hardcoded
`0.2% CPU · energy 2.1` is exactly the claim non-negotiable 8 exists to stop.
Showing your own cost in your own chrome is a claim only an honest utility can
make, and only if the number is measured.

The public IP row moved into the Network section. The rail has no room for it
and no business holding it.

---

## Responsive

Fluid by default. `clamp()` on type, `auto-fit` / `minmax()` on every grid so
readouts and rows reflow without breakpoints.

**There is no 1080px breakpoint any more.** The sidebar is 214pt at every width
and does not collapse, so the old sidebar collapse has nothing left to do.

**≤ 760px.** Content padding tightens to `18px 16px 32px`. Tables and device
rows drop to two columns, and the row annotation moves inline beside its value
instead of below it.

Verified with no horizontal overflow at 1520, 1200, 1000, 820 and 720px —
against the 64px icon rail and the unscaled type. **Not re-verified since the
214pt sidebar and the ×1.32 scale**, which leave 506pt of content at the 720pt
minimum, and a readout card's minimum is 210pt, so two cards per row is the most
that fits there. Re-walk the widths before treating this as settled.

Minimum window: 720 × 560.

---

## Motion

| Event | Duration | Curve |
|---|---|---|
| Section enter | 550 ms, `translateY(12px)` and fade — it rides the colour-world curve rather than one of its own | `cubic-bezier(.16,1,.3,1)` |
| Colour world change | 550 ms | same |
| Core bar height | 600 ms | same |
| Rail item hover | 220 ms | same |
| Cell and row hover | 200–250 ms | same |
| Press feedback | 160–180 ms | same |
| Live dot pulse | 2.2 s loop | ease-in-out |

The 7.5s object breathe is gone, along with the object it belonged to.
`Animation.fathomEnter` in `FathomDesign.swift` still declares the 450 ms curve
and nothing references it; `FathomRootView` drives the transition with
`.fathomWorld`. Wire it up or delete it, but do not restate 450 ms here while
0.55 is what runs.

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
sparse file."* Every hand-drawn chart — sparkline, core bars, segment bar and
day columns — carries a composed label that names its source. The static audit
of 25 August verified all four and fixed the two that spoke incomplete figures.

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

Every figure below composites the whole field under the plate — the world's
bottom stop, the brightest speckle the grain's band permits, and the white 15%
highlight — because the plate sits on top of all of it and the ground under text
is lighter than the bottom stop wherever they land.

Bluetooth `#2CBE7C` and Storage `#2BB6D4` are the two worst worlds and sit
within 0.002 of each other on every surface, so which of them the gate names as
worst varies by surface and means nothing. These are the figures it prints:

| Surface | Stack | Worst world |
|---|---|---|
| Content plate — display title, full white | `.45` | 5.95:1 |
| Content plate — body text at 82% | `.45` | 4.60:1 |
| Rail — selected, full white | `.45` | 5.95:1 |
| Rail — unselected at 82% | `.45` | 4.60:1 |
| Readout cell, card, tile | `.45` + `.16` | 5.75:1 |
| Data row | `.45` + `.07` | 5.07:1 |
| Data row, hover | `.45` + `.13` | 5.51:1 |

Run `scripts/check-contrast.py` rather than trusting this table. It prints all
of it, and it is what CI enforces.

**Why 45% and not 40%.** 40% is what the bottom stop alone appears to allow, and
it is wrong: under the highlight the same surface renders 4.18:1. The minimum
that survives the highlight is 44%, and 45% is that with a little room. Measuring
the gradient without the highlight overstates every result on this screen, which
is why the gate now reads the highlight from source too.

**The highlight is drawn at half the strength the prototype specifies.** The
prototype's `#halo` peaks at white 30% and falls to 10% at 42% of its radius;
the app draws 15% and 5%, the same ramp halved. This is the contrast rule
winning over the visual spec, as `AGENTS.md` requires: at the prototype's 30%,
body text on the bare plate measures **4.24:1** on Storage and fails outright.
Deepening the plate instead would work — 48% carries a 30% highlight at 4.58:1
— but the plate is already the heaviest thing between the reader and the colour,
and 48% is a darker app for a highlight nobody is reading. Only the strength
changed. The geometry is the prototype's, transcribed rather than approximated:
an ellipse centred at `(0.60, 0.29)` of the window with radii
`(0.416w, 0.510h)`, proportional so it looks the same on a 13-inch display and a
32-inch one.

**The materials are black where the original handoff drew them white.** The
largest of the departures on this page, and a deliberate one. On a plate, a
white tint lightens back toward the field the plate exists to escape — the
design's white 7% row measures 1.96:1 and its lightening 13% hover 3.60:1, both
short of the rule. The magnitudes the design chose are kept exactly; only the
sign is flipped. The prototype has since been regenerated with the black values
(`--plate:rgba(0,0,0,.45)`, `--cell:rgba(0,0,0,.16)`, `--row:rgba(0,0,0,.07)`,
`--rowh:rgba(0,0,0,.13)`), so this is now a record of the decision rather than a
live disagreement. Which is the same conclusion the next paragraph reached the
first time.

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
82% — with **0.10** of margin. A world with a brighter bottom stop than
Bluetooth's `#2CBE7C` or Storage's `#2BB6D4` will fail the gate. Check before
adding one.

**One layer under the plate is still unmodelled, and it is under the tightest
surface.** `FathomRail` puts `.ultraThinMaterial.opacity(0.18)` beneath its
plate, standing in for the prototype's `backdrop-filter: blur(46px)
saturate(135%)`. A material's composite depends on the wallpaper and the display
and cannot be computed from source, so the gate cannot model it — and the rail's
unselected icons at 82% are the joint-tightest surface in the app, with 0.10 to
give. If anything erodes on a real display it will be there first. That is a
reading for the reference machine, and the only one the gate cannot take.

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
