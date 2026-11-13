---
version: 1
slug: "spike-rootview-swift"
primary_target: "Spike/RootView.swift"
related_targets: ["Spike/ChallengeView.swift","Spike/LogView.swift"]
---

Scope: the Wakelatch iOS app's screens (spike first: Tomorrow/arm, Challenge, Log). Mode: Operate.
Audience and job: groggy sleeper in a dark room stopping a latched alarm; at night, setting tomorrow's two times.
Constraints: native SwiftUI controls and navigation, Dynamic Type, VoiceOver, Reduce Motion, dark-room first.
Memorable moment: the red signal disc at twelve on the dial, holding until the challenge is solved, then dropping away.
Unresolved: sound set, history screen, app icon artwork.

## Direction contract

THESIS: The Swiss railway clock whose red second hand waits at twelve for the signal. Wakelatch is that pause: rings hold until you give the signal. Refuses sunrise gradients, neon-on-black and the stock alarm list.
OWN-WORLD: Enamel black ground (#0B0D10) in both appearances on morning screens, white bar indices, graphite secondary text, one signal red (#E1251B) reserved for "latched". Tint is clock white on dark, black on light. SF Pro with tabular digits; bar-index dial as the one recurring form at every size.
STORY: At night the user sees tomorrow as a dial with the Ideal-to-Deadline window and every ring marked, and trusts what will happen. In the morning they see one dial, one sentence, one challenge, and are released when the disc drops.
FIRST VIEWPORT: NavigationStack, large title "Tomorrow". Full-width dial (60 bar indices; window as thick white arc; rings as long red/white ticks). Under it, an inset grouped list: Ideal, Deadline, guard interval, rings. Primary action "Arm latch" as the one prominent button. Morning: black full-screen, dial top third, "Ring 3 of 10. Solve to stop.", problem in large tabular digits, answer field, system number pad.
FORM: Station Clock, candidate 3 of 7; seed:1a69d11483defcc5
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
