---
name: Wakelatch
description: Station Clock. A dark-room alarm whose red signal disc waits at twelve until you solve.
colors:
  enamel: "#0B0D10"
  face: "#F2F2EE"
  graphite: "#8A8F98"
  signal: "#E1251B"
  face-well: "#F2F2EE14"
  face-disabled: "#F2F2EE59"
typography:
  display:
    fontFamily: "SF Pro (Dynamic Type .largeTitle)"
    fontSize: "34px"
    fontWeight: 700
    lineHeight: "41px"
    fontFeature: "tnum"
  numeral-entry:
    fontFamily: "SF Pro (Dynamic Type .title)"
    fontSize: "28px"
    fontWeight: 400
    lineHeight: "34px"
    fontFeature: "tnum"
  headline:
    fontFamily: "SF Pro (Dynamic Type .title2)"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: "28px"
  title:
    fontFamily: "SF Pro (Dynamic Type .title3)"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: "25px"
  label:
    fontFamily: "SF Pro (Dynamic Type .headline)"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: "22px"
  body:
    fontFamily: "SF Pro (Dynamic Type .body)"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: "22px"
  body-secondary:
    fontFamily: "SF Pro (Dynamic Type .subheadline)"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: "20px"
    fontFeature: "tnum"
  caption:
    fontFamily: "SF Pro (Dynamic Type .footnote)"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: "18px"
    fontFeature: "tnum"
rounded:
  slab: "12px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "20px"
  xl: "24px"
  stack: "28px"
components:
  button-slab:
    backgroundColor: "{colors.face}"
    textColor: "{colors.enamel}"
    typography: "{typography.label}"
    rounded: "{rounded.slab}"
    height: "56px"
    width: "100%"
  button-slab-disabled:
    backgroundColor: "{colors.face-disabled}"
    textColor: "{colors.enamel}"
    rounded: "{rounded.slab}"
    height: "56px"
  answer-field:
    backgroundColor: "{colors.face-well}"
    textColor: "{colors.face}"
    typography: "{typography.numeral-entry}"
    rounded: "{rounded.slab}"
    padding: "12px 0"
    width: "100%"
  station-dial:
    backgroundColor: "{colors.enamel}"
    textColor: "{colors.face}"
    width: "100%"
  station-dial-challenge:
    backgroundColor: "{colors.enamel}"
    size: "220px"
  station-dial-challenge-ax:
    backgroundColor: "{colors.enamel}"
    size: "140px"
  signal-disc:
    backgroundColor: "{colors.signal}"
    rounded: "50%"
---

# Design System: Wakelatch

## Overview

**Creative North Star: "The Station Clock"**

Wakelatch is a Swiss railway clock in a dark room. The red second hand on those clocks pauses at twelve and waits for the signal before it moves on. Wakelatch is that pause: a latched alarm keeps ringing until the user gives the signal by solving the challenge, and then the red disc swings away. Everything else on screen is the clock's enamel, its white bar indices and its graphite minor marks.

The app is dark-only. Both scenes it serves happen in a dark room: setting tomorrow's rings at night, and solving the challenge in the morning with bleary eyes and one hand. Screens are sparse and high-contrast: white on near-black, one dial, one sentence, one action pinned to the bottom. Native SwiftUI structure (NavigationStack, inset grouped lists, system toolbars, the system number pad) carries the app; the world lives in the colours, the dial and the single slab button. The direction refuses sunrise gradients, neon-on-black and the stock alarm list.

The world is flat. There are no custom shadows or gradients; depth comes from the system's own grouped-list and toolbar materials, and from the white slab sitting on enamel.

**Key Characteristics:**
- Dark-only enamel ground (no light appearance).
- One recurring form: the bar-index station dial, at every size.
- Signal red means "latched" and nothing else.
- SF Pro at Dynamic Type text styles, tabular digits everywhere a number appears.
- One radius (12pt) and one button style (slab).
- The primary action is pinned in the bottom safe-area inset.

## Colors

Three clock materials and one signal: enamel black, clock-face white, graphite, and a red that only ever means "latched".

### Primary
- **Clock-Face White** (`face`): primary text, the major bar indices, the ring ticks, the ring-window arc (at 90% opacity), the slab button fill, and the app tint (toolbar items, pickers, toggles, links). Roughly 18:1 on enamel.

### Tertiary
- **Signal Red** (`signal`): the signal disc, its stem and hub, and the tick of the ring that is sounding now on the challenge dial. It appears only while a latch holds. It is never used for text, never for errors, never for buttons.

### Neutral
- **Enamel Black** (`enamel`): the ground of every screen, behind lists (with the list's own background hidden) and the full-screen challenge. Slightly cool, so the white reads as enamel paint rather than paper.
- **Graphite** (`graphite`): the 48 minor dial indices, secondary text (next/last ring line, the wrong-answer line, probe results) and text-field placeholders. 6.3:1 on enamel.
- **Face Well** (`face-well`, clock white at 8%): the fill behind the answer field. The only tinted surface the app draws itself.
- **Face Disabled** (`face-disabled`, clock white at 35%): the slab button's fill when disabled.

System colours are used as-is where the system owns the control: grouped-list section fills, separators, the toolbar glass, the number pad, and the system red of destructive buttons (see Named Rules).

### Named Rules
**The Signal Rule.** Signal red means "latched" and nothing else. If the latch is not holding, no red is on screen. It is never used for text.

**The Destructive Exception Rule.** Destructive buttons ("Cancel chain", "Clear log") keep the system red that `role: .destructive` gives them. This is a deliberate exception to the Signal Rule, following the HIG convention that destructive actions are shown in the system red. Do not restyle them in signal red, and do not use the system red anywhere else.

**The Quiet Error Rule.** Errors are shown in clock-face white with an SF Symbol (`exclamationmark.triangle`), at footnote size. Never in red.

**The Dark Room Rule.** The app is dark-only (`.preferredColorScheme(.dark)` at the root and on the challenge cover). Both use scenes happen in a dark room. Do not add a light appearance.

## Typography

**Display Font:** SF Pro (system), through Dynamic Type text styles
**Body Font:** SF Pro (system), through Dynamic Type text styles
**Label/Mono Font:** none; numbers use SF Pro's tabular figures (`.monospacedDigit()`)

**Character:** The system face, set like a station timetable: bold where it must be read from across a dark room, tabular wherever a number can change, nothing decorative.

Sizes below are points at the default (Large) content size; every role scales with Dynamic Type.

### Hierarchy
- **Display** (`.largeTitle`, bold, tabular): the challenge problem ("22 + 51 + 83"). One line, shrinks to 60% before it would wrap.
- **Numeral entry** (`.title`, regular, tabular, centred): the typed answer in the answer field.
- **Headline** (`.title2`, semibold, centred): the one morning sentence ("Ring 3 of 10. Solve to stop.", "Released.").
- **Title** (`.title3`, semibold): the home status line ("Latched. 7 rings.", "Nothing armed.").
- **Label** (`.headline`, semibold): the slab button label.
- **Body** (`.body`): list rows, pickers, steppers, toggles; system defaults.
- **Body secondary** (`.subheadline`, tabular, graphite): the next/last ring line and the wrong-answer line.
- **Caption** (`.footnote`, tabular): log lines, probe results, the error label.

Navigation titles are the system large title on the home screen and inline on pushed screens.

### Named Rules
**The Timetable Rule.** Every number that can change (times, ring counts, problems, answers, log timestamps) uses tabular digits, so values never jitter as they update.

**The Text Style Rule.** Type is set only with Dynamic Type text styles (weight may change; size may not be fixed). No custom fonts, no fixed point sizes.

## Layout

Single column, phone only. Home and Log are inset grouped lists on enamel; the dial and status line sit in the first section with clear row backgrounds and hidden separators, so they read as part of the ground rather than in a card. The dial fills the column width (8pt inset).

The challenge is a full-screen cover: a vertical stack with 28pt between dial, sentence, problem and answer field, 24pt side margins, centred text. The stack scrolls only when its content overflows (`scrollBounceBehavior(.basedOnSize)`). The dial is 220pt wide; at accessibility type sizes it shrinks to a fixed 140pt and its top padding drops from 24pt to 8pt, so the whole challenge (dial, sentence, problem, field, button) fits above the number pad.

The primary action is pinned in a bottom `safeAreaInset`, never placed in the scrolling content: 20pt side padding on home (matching the list's margins), 24pt on the challenge, 12pt above and below. Content scrolling under it fades through a soft scroll-edge effect (`scrollEdgeEffectStyle(.soft)`, bottom on home, top and bottom on the challenge).

Spacing steps observed: 4 (status line stack), 8 (dial inset), 12 (button inset, answer field padding, field-to-feedback), 20 and 24 (side margins), 28 (challenge stack).

### Named Rules
**The Pinned Action Rule.** Each screen has at most one slab, and it lives in the bottom safe-area inset with a soft scroll edge behind it.

**The Fits Above the Keys Rule.** At any Dynamic Type size, the morning challenge must show its whole task above the number pad. Shrink the dial before anything else.

## Elevation & Depth

Flat. The app draws no shadows, blurs or gradients of its own. Depth comes from the system: grouped-list section fills, the toolbar's glass buttons, the keyboard. The app's own layering is limited to the white slab on enamel and the 8% face well behind the answer field.

### Named Rules
**The Enamel Rule.** Custom surfaces are enamel, clock white, or clock white at a stated opacity. No shadows, no gradients.

## Shapes

One radius, 12pt (`rounded.slab`), on every custom rounded surface: the slab button and the answer field. System containers (grouped list sections, toolbar buttons, the keyboard) keep their system shapes and are not restyled to match. The dial's form language is the bar: butt-capped straight strokes for indices and ring ticks; only the ring-window arc has round caps. The signal disc is the only circle.

## Components

### Buttons
The slab: a clock-white block with a black label that presses down. It is the only custom button style.
- **Shape:** gently rounded block (12pt), full width, at least 56pt tall.
- **Primary:** clock-face white fill, enamel label, `.headline` type.
- **Pressed:** scales to 98% and drops to 85% opacity, ease-out over 0.12s.
- **Disabled:** fill drops to 35% white; label stays enamel.
- **Other buttons:** system styles in the app tint (clock white): toolbar items, list buttons, `NavigationLink`, `ShareLink`. Destructive actions use `role: .destructive` and keep the system red.

### Inputs / Fields
- **Style:** the answer field is a borderless block filled with clock white at 8%, 12pt radius, 12pt vertical padding, centred tabular `.title` digits. Placeholder in graphite. System number pad.
- **Focus:** focused automatically when the challenge appears; the system caret in clock white is the only focus mark.
- **Error:** a wrong answer clears the field, swaps in a new problem, plays the error haptic, and shows a graphite line under the field.

### Lists
- **Style:** system inset grouped lists with the list background hidden over enamel. Section headers and footers are system styles. Rows hold native pickers, steppers and toggles, tinted clock white.

### Navigation
- **Style:** NavigationStack with a system large title on home and inline titles on pushed screens. Toolbar items are system glass buttons. The challenge is a full-screen cover with interactive dismissal disabled; it leaves only when solved.

### Station Dial (signature)
A railway-clock face drawn in a Canvas, used on home and on the challenge, the one recurring form at every size.
- **Indices:** 60 bar indices. The 12 majors are clock white (20% of radius long, 4.5% wide); the minors are graphite (7% long, 1.6% wide).
- **Ring window:** a thick clock-white arc (90% opacity, round caps) at half radius spanning first to last ring.
- **Rings:** a long clock-white tick for each scheduled ring at its minute position. On the challenge, the ring sounding now is drawn thicker in signal red.
- **Signal disc:** while latched, a red disc on a thin stem with a small hub, parked at twelve. Hidden from VoiceOver; the dial reads as one element ("Latched. 7 rings scheduled.").
- **Release:** when the latch releases, the disc swings 110° clockwise around the dial's centre and fades out (spring, 0.5s), with a success haptic. Under Reduce Motion it crossfades instead (ease-out, 0.2s). The cover dismisses one second later.
- **Arming:** on home, the disc appears and disappears with a 0.5s spring.

## Do's and Don'ts

### Do:
- **Do** keep every screen dark: enamel ground, `.preferredColorScheme(.dark)`.
- **Do** reserve signal red for the latched state: the disc and the ring sounding under the latch.
- **Do** show errors in clock-face white with an SF Symbol.
- **Do** leave destructive buttons in the system red of `role: .destructive`, per the HIG.
- **Do** set all type with Dynamic Type text styles and give every changing number tabular digits.
- **Do** pin the one primary action in a bottom safe-area inset with a soft scroll-edge effect.
- **Do** use the slab for the primary action and system button styles, tinted clock white, for everything else.
- **Do** use the 12pt radius on any new custom rounded surface.
- **Do** make the station dial the visual centre of any screen about the latch, and shrink it (140pt) at accessibility sizes before dropping content.
- **Do** pair the release with the success haptic and give it a crossfade under Reduce Motion.

### Don't:
- **Don't** use signal red for text, errors, buttons, badges or decoration.
- **Don't** add a light appearance.
- **Don't** add a second custom button style or a second radius.
- **Don't** fix font sizes or bring in a custom typeface.
- **Don't** add shadows or gradients; the world refuses sunrise gradients and neon-on-black.
- **Don't** replace the dial with the stock alarm list.
- **Don't** put the primary action inside scrolling content.

## Open Items

- Increase Contrast variants of the four colours are not built yet.
- There is no app icon yet.
