# FATHOM — logo and app icon brief

A prompt for designing the mark. Everything here is drawn from the existing
design system in `FATHOM-DESIGN.md` and the locked prototype `fathom-app.html`,
so a mark made from this brief will sit inside the product rather than beside it.

---

## What the word means

**Fathom** is a unit of *depth* — six feet, historically the span of a sailor's
outstretched arms, used to sound how deep the water is. To **fathom** something
is to understand it.

Both meanings are the product. FATHOM sounds the depth of your disk and reports
what is actually down there. The name was chosen because measuring depth and
understanding are the same act.

## What the product is

A macOS utility that tells the truth about storage, memory and SSD endurance.

Its one-sentence position: *every other Mac utility shows you a number it cannot
justify; FATHOM shows you two numbers and names the one it does not know.*

For every file it reports **two** numbers — *on disk* and *freed if deleted* —
because a cloned, sparse, or still-open file frees far less than its size
suggests. Where macOS will not publish a value, FATHOM renders the row greyed
and says **not published** rather than estimating. There is deliberately no
health score, no letter grade, no green tick, no red badge.

**The mark should feel like an instrument, not a cleaner.** Calm, precise,
slightly serious. It measures; it does not alarm.

---

## The prompt

> Design a macOS app icon for **FATHOM**, a precision instrument that measures
> the true depth of disk storage.
>
> The mark is **one lit three-dimensional object floating in a saturated colour
> field**, lit from above, casting a soft shadow — like a single specimen under
> studio light. It is rendered, not flat; dimensional, not skeuomorphic.
>
> The concept to explore is **sounding depth**: a plumb line, a sounding weight
> on a cord, a stack of strata read from above, a disc seen edge-on with layers
> below the surface, or concentric depth rings. The idea that what you see on the
> surface is not the whole of what is there.
>
> **Colour:** the deep-ocean field of the Storage world — a vertical gradient
> from near-black navy `#04263A` at the top, through `#0C6B90`, to a luminous
> cyan `#2BB6D4` at the bottom, as though light is coming *up* from below. The
> object itself sits between a pale highlight `#C4F2FA` and a deep `#176980`.
>
> **Lighting model**, in this order: a cast shadow beneath; a body with a radial
> highlight at upper-left over a 152° light-to-dark ramp; radial darkening at the
> lower right; a blurred white *bounce* along the lower edge, light returning
> from below; a small rotated specular ellipse near the top-left; a 1.5px inner
> rim at 30% white; and a brighter 2px top edge at 48% white.
>
> **Silhouette:** a macOS squircle. The object inside should read as a single
> confident shape at 1024px and still be identifiable at 16px in the menu bar.
>
> Mood: quiet, exact, deep water. Scientific rather than corporate. No mascot,
> no gloss-for-gloss's-sake, no gradient mesh noise.

---

## Hard constraints

- **macOS app icon geometry.** Squircle, full bleed, no drop-shadow baked into
  the canvas beyond the object's own. Deliverable at 1024, 512, 256, 128, 64,
  32 and 16px. It must survive 16px — test there before falling in love with it.
- **Legible on both light and dark desktops.** The icon sits on user wallpaper,
  not on our gradient.
- **A monochrome menu-bar variant** is required and is the harder problem: a
  single-colour template glyph, no gradient, no fill tricks, readable at 16px
  against both a light and a dark menu bar.
- **Contrast ≥ 4.5:1** for anything that reads as text or a numeral.
- **No letter grades, ticks, shields, warning triangles, brooms, sparkles or
  progress rings.** These are the visual language of exactly the products FATHOM
  is positioned against. A shield says "you are at risk"; this product's whole
  argument is that a full disk is not an emergency.
- **No literal magnifying glass or hard-drive platter cliché** unless it earns
  its place — the current icon is a stack of platters and is the thing to beat.

---

## What exists today

`Fathom/Resources/Assets.xcassets/AppIcon.appiconset/` holds the current icon:
a stack of translucent discs in the Storage blue with a glowing vertical line
running down through them. It reads as *layers with something measured through
them*, which is the right idea. It is a starting point and not sacred — the
sounding-line concept is the part worth keeping.

The section objects in `fathom-app.html` show the rendering treatment applied
across twenty silhouettes; open it in a browser to see the lighting model in
motion before drawing anything.

---

## Wordmark

Set in **Bricolage Grotesque ExtraBold**, the product's display face, tracked
tight at roughly −0.037em to match the screen titles. All caps: **FATHOM**.

The word is six letters, symmetrical enough to sit under or beside the mark
without adjustment. Resist decorating it — no depth lines through the letters,
no gradient fill. The object carries the concept; the wordmark just names it.
