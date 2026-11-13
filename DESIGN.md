---
name: Wakelatch
description: Station Clock. A dark-room alarm whose red signal disc waits at twelve until you solve.
colors:
  enamel: "#0B0D10"
  bedside-black: "#000000"
  face: "#F2F2EE"
  graphite: "#8A8F98"
  signal: "#E1251B"
  face-well: "#F2F2EE14"
  face-chip-on: "#F2F2EE29"
  face-chip-off: "#F2F2EE0A"
  face-disabled: "#F2F2EE59"
  system-red: "#FF453A"
typography:
  clock-display:
    fontFamily: "SF Pro (system, @ScaledMetric relativeTo .largeTitle)"
    fontSize: "72px"
    fontWeight: 600
    fontFeature: "tnum"
  bedside-clock:
    fontFamily: "SF Pro (system, @ScaledMetric relativeTo .largeTitle)"
    fontSize: "64px"
    fontWeight: 600
    fontFeature: "tnum"
  count-display:
    fontFamily: "SF Pro (system, @ScaledMetric relativeTo .largeTitle)"
    fontSize: "96px"
    fontWeight: 700
    fontFeature: "tnum"
  display:
    fontFamily: "SF Pro (Dynamic Type .largeTitle)"
    fontSize: "34px"
    fontWeight: 700
    lineHeight: "41px"
    fontFeature: "tnum"
  time-display:
    fontFamily: "SF Pro (Dynamic Type .largeTitle)"
    fontSize: "34px"
    fontWeight: 600
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
    fontWeight: 400
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
  footnote:
    fontFamily: "SF Pro (Dynamic Type .footnote)"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: "18px"
  caption:
    fontFamily: "SF Pro (Dynamic Type .caption)"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: "16px"
rounded:
  slab: "12px"
spacing:
  xs: "4px"
  chip-gap: "6px"
  sm: "8px"
  md: "12px"
  card: "14px"
  lg: "20px"
  xl: "24px"
  stack: "28px"
  top: "32px"
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
  button-text:
    textColor: "{colors.face}"
    typography: "{typography.body}"
    height: "44px"
    width: "100%"
  skip-link:
    textColor: "{colors.graphite}"
    typography: "{typography.footnote}"
    size: "44px"
  time-card:
    backgroundColor: "{colors.face-well}"
    textColor: "{colors.face}"
    typography: "{typography.time-display}"
    rounded: "{rounded.slab}"
    padding: "{spacing.card}"
  day-chip-selected:
    backgroundColor: "{colors.face-chip-on}"
    textColor: "{colors.face}"
    typography: "{typography.body-secondary}"
    rounded: "{rounded.slab}"
    height: "44px"
  day-chip-unselected:
    backgroundColor: "{colors.face-chip-off}"
    textColor: "{colors.graphite}"
    typography: "{typography.body-secondary}"
    rounded: "{rounded.slab}"
    height: "44px"
  answer-field:
    backgroundColor: "{colors.face-well}"
    textColor: "{colors.face}"
    typography: "{typography.numeral-entry}"
    rounded: "{rounded.slab}"
    padding: "{spacing.card}"
    width: "100%"
  toggle-alarm:
    backgroundColor: "{colors.graphite}"
    textColor: "{colors.face}"
  button-destructive:
    textColor: "{colors.system-red}"
    typography: "{typography.body}"
  station-dial-home:
    backgroundColor: "{colors.enamel}"
    width: "260px"
  station-dial-ringing:
    backgroundColor: "{colors.enamel}"
    size: "200px"
  station-dial-challenge:
    backgroundColor: "{colors.enamel}"
    size: "140px"
  station-dial-challenge-ax:
    backgroundColor: "{colors.enamel}"
    size: "96px"
  station-dial-bedside:
    backgroundColor: "{colors.bedside-black}"
    width: "220px"
  signal-disc:
    backgroundColor: "{colors.signal}"
    rounded: "50%"
---

# Design System: Wakelatch

## Overview

**Creative North Star: "The Station Clock"**

Wakelatch is a Swiss railway clock in a dark room. The red second hand on those clocks pauses at twelve and waits for the signal before it moves on. Wakelatch is that pause: a latched alarm keeps ringing until the user gives the signal by finishing the challenge, and then the red disc swings away. Everything else on screen is the clock's enamel, its white bar indices and its graphite minor marks.

The app is dark-only. Every scene it serves happens in a dark room: setting tomorrow's two times at night, leaving the phone on the charger in bedside mode, and stopping the ring in the morning with bleary eyes and one hand. Screens are sparse and high-contrast: white on near-black, one dial, one sentence, one white slab at the bottom. Native SwiftUI structure (NavigationStack, inset grouped lists and forms, system toolbars and sheets, the wheel and compact time pickers, the system number pad) carries the app; the world lives in the colours, the dial, the large tabular numbers and the single slab. The direction refuses sunrise gradients, neon-on-black and the stock alarm list.

The world is flat. There are no custom shadows or gradients; depth comes from the system's grouped-list, toolbar and sheet materials, and from clock white at stated opacities sitting on enamel.

**Key Characteristics:**
- Dark-only: enamel ground everywhere, pure black at the bedside.
- One recurring form: the bar-index station dial, at every size from 96pt to full width.
- Signal red means "latched" and nothing else, and is never text.
- SF Pro only; tabular digits on every number; the big clock and count numbers scale with Dynamic Type up to a cap.
- One radius (12pt) and one custom button (the slab), one slab per screen at the bottom.

## Colors

Three clock materials and one signal: enamel black, clock-face white, graphite, and a red that only ever means "latched".

### Primary
- **Clock-Face White** (`face`): primary text, the major bar indices, the ring ticks, the ring-window arc (at 90%), the slab fill, the progress bar and eyes-open ring, and the app tint (toolbar items, pickers, links, the AlarmKit alert tint).

### Tertiary
- **Signal Red** (`signal`): the signal disc with its stem and hub, and the tick of the ring that is sounding now on the ringing and challenge dials. It appears while a latch is armed or holding, and once as an illustration of the latch on the onboarding welcome dial. Never text, never errors, never buttons.

### Neutral
- **Enamel Black** (`enamel`): the ground of every screen and sheet (lists and forms hide their own background over it), and the launch screen colour.
- **Bedside Black** (`bedside-black`): the ground of bedside mode only. Pure black so an OLED screen left on all night emits nothing but the dimmed clock.
- **Graphite** (`graphite`): the 48 minor dial indices, secondary text (ring lines, card labels and captions, footers of our own, history line, wrong-answer lines, the bedside exit line), placeholders, unselected day-chip text, the Skip link, and the "Alarm on" toggle's on-track. 6.3:1 on enamel.
- **Face Well** (`face-well`, clock white at 8%): the fill of the time cards, the onboarding time rows and the answer field.
- **Chip On / Chip Off** (`face-chip-on` at 16%, `face-chip-off` at 4%): weekday chip fills.
- **Face Disabled** (`face-disabled`, clock white at 35%): the slab's fill when disabled.

System colours stay as the system draws them where the system owns the control: grouped-list section fills, separators, toolbar glass, sheets, the keyboard, and the system red of destructive buttons (`system-red` is the dark-mode value iOS supplies, not an app colour).

### Named Rules
**The Signal Rule.** Signal red means "latched" and nothing else: the disc while a latch is armed or holding, and the tick of the ring sounding now. It is never used for text.

**The Destructive Exception Rule.** Destructive buttons ("Skip this morning") keep the system red that `role: .destructive` gives them. This is a deliberate exception to the Signal Rule, following the HIG convention for destructive actions. Do not restyle them in signal red, and do not use the system red anywhere else.

**The Quiet Error Rule.** Errors and warnings are a `Label` in clock-face white with the `exclamationmark.triangle` symbol. Never red.

**The Dark Room Rule.** The app is dark-only (`.preferredColorScheme(.dark)` at the root, on the morning screens and on the skip sheet). Do not add a light appearance.

**The Bedside Black Rule.** Bedside mode alone uses a pure black ground. Its clock group (dial, time, first-ring line) is dimmed as one layer (`compositingGroup()` then 55% opacity) so overlapping strokes do not show through each other; the exit line underneath stays full graphite so it stays legible.

## Typography

**Display Font:** SF Pro (system)
**Body Font:** SF Pro (system), through Dynamic Type text styles
**Label/Mono Font:** none; numbers use SF Pro's tabular figures (`.monospacedDigit()`)

**Character:** The system face, set like a station timetable: big and semibold where it must be read across a dark room, tabular wherever a number can change, nothing decorative.

Sizes are points at the default (Large) content size.

### Hierarchy
- **Clock display** (semibold, tabular, 72pt scaled, capped at 110pt): the current time on the ringing screen. One line, shrinks to 50% before wrapping.
- **Bedside clock** (semibold, tabular, 64pt scaled, capped at 96pt): the time in bedside mode.
- **Count display** (bold, tabular, 96pt scaled, capped at 140pt): the step and shake counts, with a numeric content transition.
- **Display** (`.largeTitle`, bold): the math problem (one line, 60% minimum scale), "Released.", "Still up?", onboarding headings.
- **Time display** (`.largeTitle`, semibold, tabular): Ideal and Deadline in the time cards. One line, 60% minimum scale.
- **Numeral entry** (`.title`, regular, tabular, centred): the typed math answer.
- **Headline** (`.title2`, semibold): the one morning sentence ("Ring 3 of 20. Deadline 7:10 AM."), challenge titles ("Solve to stop", "Walk", "Shake").
- **Title** (`.title3`): Released facts, "First ring 6:20 AM." at the bedside, counter units, the onboarding lead, typed-phrase entry.
- **Label** (`.headline`, semibold): the slab label, onboarding row titles.
- **Body** (`.body`): list rows and native controls; challenge picker titles in semibold.
- **Body secondary** (`.subheadline`, tabular when it carries times): the home summary line, the challenge ring line, card labels and day chips in semibold, picker summaries.
- **Footnote** (`.footnote`): the Skip link, the bedside exit line, time-sheet notes, card chevrons.
- **Caption** (`.caption`): the line under each time ("When you must be up").

Navigation titles are the system large title on home ("Tomorrow", "This morning", a weekday, or "Alarm off") and inline on pushed screens and sheets.

### Named Rules
**The Timetable Rule.** Every number that can change (times, ring counts, problems, answers, step and shake counts) uses tabular digits, so values never jitter as they update.

**The Scaled Clock Rule.** Type is set with Dynamic Type text styles. The three big numbers are the only fixed-size sets, and each is a `@ScaledMetric(relativeTo: .largeTitle)` with a cap: 72 to 110, 64 to 96, 96 to 140. No custom fonts.

## Layout

Single column, phone only. Home, Settings, the challenge picker and the skip sheet are inset grouped lists or forms on enamel. On home the dial (up to 260pt, centred), the two time cards and the summary line sit in the first section with clear row backgrounds and hidden separators, so they read as part of the ground.

Morning screens are vertical stacks with 24pt side margins and 16 to 28pt between elements; the dial sits at the top (200pt ringing and released, 180pt awake check, 140pt on the challenge). The challenge scrolls only when its content overflows (`scrollBounceBehavior(.basedOnSize)`, soft edges top and bottom). At accessibility type sizes the challenge dial drops to 96pt so the problem and answer field stay above the number pad; the math answer checks itself once it has as many digits as the right answer. The emergency Skip sits in the top-trailing corner (44pt target, 12pt trailing inset), always visible and far from the keypad.

Onboarding is a scrolling column capped at 520pt, 24pt margins, 32pt top, 20pt between blocks. Bedside mode centres its dimmed group (28pt spacing, dial at 220pt) between spacers and puts the exit line 24pt off the bottom.

The primary action sits in a bottom `safeAreaBar` (home, 20pt sides) or `safeAreaInset` (morning and onboarding, 24pt sides, 8pt bottom), above a soft scroll edge. A secondary text button ("Snooze until 7:07 AM", "Open Settings") may sit under the slab at 8pt, full width, 44pt tall.

Spacing steps in use: 4, 6 (between day chips), 8, 12, 14 (card and field padding), 20, 24, 28, 32.

### Named Rules
**The One Slab Rule.** Each screen has at most one white slab, and it lives in a bottom safe-area bar or inset, never in scrolling content.

**The Fits Above the Keys Rule.** At any Dynamic Type size, the math challenge shows its problem and answer field above the number pad. Shrink the dial first.

## Elevation & Depth

Flat. The app draws no shadows, blurs or gradients of its own. Depth comes from the system: grouped-list section fills, the toolbar's glass buttons, sheets, the keyboard and the soft scroll-edge effect behind the bottom bar. The app's own layering is clock white at stated opacities (4, 8, 16, 35, 90%) on enamel.

### Named Rules
**The Enamel Rule.** Custom surfaces are enamel, clock white, or clock white at a stated opacity. No shadows, no gradients.

## Shapes

One radius, 12pt (`rounded.slab`), on every custom rounded surface: the slab, time cards, onboarding time rows, the answer field and day chips. System containers keep their own shapes. The dial's form language is the bar: butt-capped straight strokes for indices and ring ticks; only the ring-window arc has round caps. Circles are kept for the signal disc and hub and the eyes-open camera with its progress ring (220pt, 8pt round-capped clock-white stroke).

## Components

### Buttons
The slab: a clock-white block with a black label that presses down. It is the only custom button style.
- **Shape:** gently rounded block (12pt), full width, at least 56pt tall.
- **Primary:** clock-face white fill, enamel label, `.headline` type. Labels are short verbs: "Start challenge", "Stop", "Solve to stop", "I'm up", "Done", "Bedside mode", "Continue", "Set alarm".
- **Pressed:** scales to 98% and drops to 85% opacity, ease-out over 0.12s.
- **Disabled:** fill drops to 35% white; label stays enamel.
- **Text button:** a plain full-width 44pt button in the clock-white tint under the slab, for the second choice ("Snooze until h:mm", "Open Settings").
- **Skip link:** "Skip (N)" in graphite footnote, top-trailing on the challenge, labelled for VoiceOver as "Emergency skip, N left this month".
- **Destructive:** `role: .destructive` in system red, inside a form section ("Skip this morning").

### Time Cards
The two times on home, side by side with 12pt between.
- **Style:** face well (8%), 12pt radius, 14pt padding. Top line: the field name in semibold subheadline and a footnote `chevron.right`, both graphite. Then the time in tabular semibold large title, clock white. Then the caption in graphite.
- **Behaviour:** tapping opens the time sheet: a medium-detent sheet with a wheel picker, a graphite footnote explaining the time, Cancel and Done in the toolbar.

### Chips (weekday repeat)
Seven equal-width chips, 6pt apart, at least 44pt tall, semibold subheadline letters, 12pt radius.
- **Selected:** clock white at 16% fill, a 1.5pt clock-white outline, clock-white letter; `.isSelected` trait.
- **Unselected:** clock white at 4% fill, no outline, graphite letter.
- VoiceOver reads the full weekday name.

### Toggles
- **Alarm on:** the system toggle tinted graphite, so the white knob reads against the on-track. Other toggles keep the app tint.

### Inputs / Fields
- **Answer field:** borderless, face well fill, 12pt radius, 14pt padding. Numeric: centred tabular `.title` on the number pad. Phrase: leading `.title3`, vertical growth. Graphite placeholder; focused on appear.
- **Wrong answer:** the field clears, a new problem appears, the error haptic plays, and a graphite line ("Not it. New problem.") shows under the field; the line's space is reserved so nothing jumps.
- **Onboarding time row:** title and graphite caption on the left, compact system time picker on the right, on the face well.

### Lists
- **Style:** system inset grouped lists and forms with their background hidden over enamel. Section headers and footers are system styles. The challenge picker rows carry an SF Symbol (32pt column), a semibold title, a graphite summary, and a checkmark on the selected row; unavailable challenges are disabled with the reason as their summary.

### Navigation
- **Style:** NavigationStack with a large title on home and inline titles elsewhere. Settings is a sheet with Done; pushed pickers use the back button. Morning screens fill the screen with interactive dismissal disabled; they leave only by the flow.

### Station Dial (signature)
A railway-clock face drawn in a Canvas, the one recurring form at every size.
- **Indices:** 60 bar indices. The 12 majors are clock white (20% of radius long, 4.5% wide); the minors are graphite (7% long, 1.6% wide).
- **Ring window:** a thick clock-white arc (90%, round caps) at about half radius from first to last ring.
- **Rings:** a long clock-white tick per ring, spread over 92% of the turn from twelve. The ring sounding now is drawn thicker in signal red.
- **Signal disc:** a red disc on a thin stem with a hub at the centre, parked at twelve. Hidden from VoiceOver; the dial reads as one element.
- **Release:** the disc swings 110° clockwise about the centre and fades (spring, 0.5s, after 0.2s on the released screen) with the success haptic. Under Reduce Motion it crossfades. The same transition arms and disarms the disc on home.

### Morning Screens
- **Ringing:** dial, the clock display, then the sentence "Ring N of M. Deadline h:mm." (nudges: "Ideal at h:mm. This one stops with a tap."; past the deadline: "Ring N of M. Past the deadline, only the challenge stops it."). Bottom: "Start challenge" slab and "Snooze until h:mm" text button.
- **Challenge:** small dial, the ring line in graphite, then the challenge. Counter challenges (steps, shake) show the count display, "of N steps" in graphite, a clock-white progress bar and a graphite instruction.
- **Awake check:** latch-free dial, "Still up?", one graphite line, "I'm up" slab.
- **Released:** the disc swings away; "Released." and the morning's facts in `.title3`, the awake-check times in graphite; "Done" slab.

### Bedside Mode
Pure black ground, status bar and system overlays hidden. The dial (latched), bedside clock and "First ring h:mm." are dimmed together to 55%; "Tap anywhere to leave." (with the charging hint when needed) sits at the bottom in full graphite footnote. The whole screen is one button that leaves.

### Alarm Sound
The system alarm (AlarmKit) uses the default iOS sound, tinted clock white. A custom sound crashed SpringBoard's tone player in the simulator and swallowed the alarm, so it is not used. Inside the app (ringing and bedside), Wakelatch plays its own synthesized chime and a softer nudge (`scripts/make-sounds.py`), ducked during the challenge.

## Do's and Don'ts

### Do:
- **Do** keep every screen dark: enamel ground, `.preferredColorScheme(.dark)`; pure black only at the bedside.
- **Do** reserve signal red for the latch: the disc and the tick of the ring sounding now.
- **Do** show errors as a clock-white `Label` with `exclamationmark.triangle`.
- **Do** leave destructive buttons in the system red of `role: .destructive`, per the HIG.
- **Do** give every changing number tabular digits, and size the big clock and count numbers with `@ScaledMetric(relativeTo: .largeTitle)` and a cap.
- **Do** put the one slab in a bottom safe-area bar or inset with a soft scroll edge behind it.
- **Do** use the slab for the primary action and system styles, tinted clock white, for everything else.
- **Do** use the 12pt radius and clock white at a stated opacity for any new custom surface.
- **Do** write morning copy as short statements of fact: "Ring N of M. Deadline h:mm.", "Snooze until h:mm".
- **Do** shrink the dial (96pt on the challenge) at accessibility sizes before dropping content.
- **Do** pair the release with the success haptic and give it a crossfade under Reduce Motion.

### Don't:
- **Don't** use signal red for text, errors, buttons, badges or decoration.
- **Don't** add a light appearance.
- **Don't** add a second custom button style or a second radius.
- **Don't** bring in a custom typeface or set uncapped, unscaled point sizes.
- **Don't** add shadows or gradients; the world refuses sunrise gradients and neon-on-black.
- **Don't** replace the dial with the stock alarm list.
- **Don't** put a slab inside scrolling content or place two slabs on one screen.
- **Don't** set a custom AlarmKit sound.

## Open Items

- The math and phrase challenges still place their Submit slab inside the scrolling content; at accessibility sizes the number pad covers it (math auto-checks, so the task still completes). Drift from the One Slab Rule, not a pattern.
- Increase Contrast variants of the colours are not built.
