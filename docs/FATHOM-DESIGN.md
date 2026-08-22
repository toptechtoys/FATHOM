# FATHOM — Design System

**Status: IN TRANSITION · 23 August 2026**
Visual spec: `fathom-app.html`. Open it. It is normative — where this document
and the prototype disagree, the prototype wins.

The prototype now carries the **Instrument Panel** direction: one always-on
window, every section a live panel of readouts behind a 64px icon rail. There is
no poster, no Scan button and no result state to wait for. It replaced the
poster direction on 23 August.

**Sections of this document not yet rewritten for it**, and therefore superseded
by the prototype wherever they disagree: *Three archetypes* (there is one
archetype now, not three), *The object* (no object is rendered), *The action
button* (no circular Scan button), the *Materials* table (white tiles and panels
became one plate with dark materials — see **The plate** below, which is
current), and *Sidebar* (a 64px icon rail in four groups, not seven named
groups at up to 244px). Read those sections as history until they are rewritten.

Current and authoritative in this document: **Colour worlds**, **Semantic
colour**, **The plate**, **Type**, **Responsive**, and **What is deliberately
absent**.

Changes go through the prototype first, then this document, then Swift. Not the
other way round.

---

## The idea in one line

Every screen is a lit object floating in a saturated colour field, and the app
tells you where you are before you read a single word.

The calibration reference was CleanMyMac. Three things were taken from it and
one was deliberately rejected.

**Taken.** Colour fills the entire window including the sidebar, so the app
reads as one lit object rather than a chrome frame around a content pane. One
large rendered object per screen, centred, with enormous space around it. Very
little text — a title, one sentence, one action.

**Rejected.** Its Assistant screen reports "Mac Health: Good", a score with no
published formula. FATHOM's Home shows the real free number, the four things
worth looking at, and the sentence *nothing is wrong*. No score, ever.

---

## Three archetypes

Getting this wrong is the most expensive mistake available. A Scan button on a
screen with nothing to scan teaches the user the app does not understand its own
data. Each of the 20 sections is exactly one of these.

### Poster → Result

Landing state is a poster: object, title, one sentence, one glowing circular
Scan button, nothing else. Press it and the same colour field fills with data.
The launch state is deliberately empty. Data appears only after the scan.

Deep Scan, Storage, Timeline, Explore, Reclaim, Endurance, Attribution,
Applications, Cloud, Maintenance, SSD Health.

### Live monitor

No Scan button. There is nothing to find; these values stream. Header with the
section name and a pulsing status pill, a row of tiles that reflows, then one
panel for detail and the honest note. Live the moment you arrive.

CPU, GPU, Memory, Sensors & Power, Network, Bluetooth.

### Surface

Neither scan nor stream. A configuration or preview screen showing the real
artefact being configured. Menu Bar renders the actual 22-point widget at true
size above its toggles. Weekly digest renders a real sample digest.

Menu Bar, Weekly digest.

---

## Colour worlds

Each section owns a three-stop field. Dark at the top, saturated at the bottom,
with a radial lift behind the object. The whole window carries it — the sidebar
is a translucent panel floating *over* the field, never a separate dark slab.

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

Transition on navigation: 550 ms, `cubic-bezier(.16,1,.3,1)`, background and
object tint together.

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

## The object

One per poster screen. Layered CSS in the prototype; a `Canvas` or layered
`ZStack` in SwiftUI. Nine layers, in order:

1. Cast shadow — 86% width, 19% height, blur 30, `rgba(0,0,0,.46)`, below
2. Body — radial highlight at 30%/20% over a 152° linear ramp, light to dark
3. Depth — radial darkening at 70%/90%
4. Bounce — blurred white ellipse along the lower edge, the light coming back up
5. Specular — blurred white ellipse at 12%/7%, rotated −20°
6. Rim — `inset 0 0 0 1.5px rgba(255,255,255,.3)`
7. Top edge — `inset 0 1px 0 2px rgba(255,255,255,.48)`
8. Glyph — white, 42% of the object, drop shadow
9. Breathe — scale 1 → 1.016, rotate 0.6°, 7.5 s, disabled under Reduce Motion

Each section has its own silhouette via `border-radius` so the shape identifies
the screen before the title is read. Squircle for Deep Scan, wide disc for
Storage, shield for Endurance, leaf for Attribution, four-lobed blob for
Reclaim. Exact values in the prototype.

Size: `clamp(150px, 23vw, 300px)`.

---

## Type

| Role | Family | Size | Tracking |
|---|---|---|---|
| Screen title | Bricolage Grotesque | `clamp(30px, 4.2vw, 52px)` | −0.037em |
| Live header | Bricolage Grotesque | `clamp(24px, 3vw, 34px)` | −0.03em |
| Hero number | Bricolage Grotesque | `clamp(42px, 6.2vw, 74px)` | −0.042em |
| Section heading | Bricolage Grotesque | `clamp(20px, 2.3vw, 27px)` | −0.028em |
| Tile / card value | Bricolage Grotesque | `clamp(22px, 2.4vw, 30px)` | −0.032em |
| Body | system UI | `clamp(13px, 1.15vw, 15.5px)` | −0.004em |
| Note | system UI | `clamp(12px, 1vw, 13px)` | 0 |
| Label | system UI 700 | 10.5px, uppercase | 0.1em |
| Data | Instrument Sans, tabular | contextual | 0 |
| Path | JetBrains Mono | 12px | 0 |

Body and note copy caps at 66 characters. Titles use `text-wrap: balance`.

**Every numeral in a column that can be compared is tabular.** Non-negotiable.

---

## Materials

| Surface | Fill | Blur | Inner light |
|---|---|---|---|
| Sidebar | `rgba(0,0,0,.20)` | 46 + saturate 135% | `.5px rgba(255,255,255,.11)` right border |
| Tile, card | `rgba(255,255,255,.105)` | 28 | `inset 0 1px 0 rgba(255,255,255,.20)` |
| Detail panel | `rgba(0,0,0,.21)` | 32 | `inset 0 1px 0 rgba(255,255,255,.14)` |
| Row | `rgba(255,255,255,.07)` | — | on hover `.13` |
| Pill | `rgba(255,255,255,.14)` | — | `inset 0 1px 0 rgba(255,255,255,.20)` |

Radii: 22px panel, 20px card, 18px tile, 12px row, 15px pill.

---

## The action button

Poster screens: a circular Scan button, `clamp(72px, 7.5vw, 94px)`, filled with
a radial of the section's own two brightest stops and haloed with
`0 0 50px 12px` of the bottom stop. It glows in the colour of the world it sits
in.

Result screens: a white pill, `clamp(42px, 4.6vh, 50px)` tall, dark text, white
halo. It reads as the resolution of the scan.

Both: hover `scale(1.04)`, active `scale(0.96)`, 160 ms.

---

## Sidebar

Width `clamp(62px, 17vw, 244px)`. Twenty items in seven groups: Surface,
Overview, System, Storage, Foresight, Manage, Hardware.

Footer carries two rows. **Public IP with country flag** — the flag is a bundled
SVG selected by country code, never fetched. Below it, the app's own idle cost:
`0.2% CPU · energy 2.1`. Showing your own cost in your own chrome is a claim
only an honest utility can make.

---

## Responsive

Fluid by default. `clamp()` on type, spacing and objects; `auto-fit` /
`minmax()` on every grid so tiles and cards reflow without breakpoints. Two
breakpoints handle structure only.

**≤ 1080px.** Sidebar collapses to a 64px icon rail — labels and group headings
hide, `title` attributes carry the names. Home stacks the ring above the feed.

**≤ 760px.** Split heroes stack. Tables drop their annotation column and tighten
to three columns. Device rows drop the meter and keep name plus value. Core bars
drop percentage labels. The chain drops its arrows and wraps two-up.

Verified with no horizontal overflow at 1520, 1200, 1000, 820 and 720px.

Minimum window: 720 × 560.

---

## Motion

| Event | Duration | Curve |
|---|---|---|
| Screen enter | 450 ms | `cubic-bezier(.16,1,.3,1)` |
| Colour world change | 550 ms | same |
| Object breathe | 7.5 s loop | ease-in-out |
| Live pill pulse | 2.2 s loop | ease-in-out |
| Button press | 160 ms | same |
| Row hover | 160 ms | ease |

Under Reduce Motion: breathe, pulse and screen-enter stop. Colour transition and
button feedback remain — they carry meaning, not decoration.

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

Contrast ≥ 4.5:1 for body text on every one of the twenty fields — the bottom
stop is the worst case, test there. Never colour alone: freeable green always
carries the word or the number too. Full keyboard navigation with a visible
focus ring at 2px white, 60% opacity. VoiceOver labels state value *and*
provenance: *"Freed if deleted, 0 gigabytes, sparse file."* Dynamic Type to
Accessibility Large without clipping.

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

`scripts/check-contrast.py` reads the worlds, the plate, every material and the
text alpha from source, composites each stack above, and fails if any of the
seven surfaces drops below 4.5:1 on any of the twenty worlds. It also refuses a
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
