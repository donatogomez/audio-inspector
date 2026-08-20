# MVP manual validation runbook

A **procedure**, not a result. Nothing here is pre-filled: run the steps against a real build and
record what actually happened in the template at the end.

This runbook exists because part of what the MVP promises **cannot** be proven from `swift test`. The
package tests run unsandboxed and never launch the `.app`, so code signing, the effective
entitlements, the powerbox, the native panels, and real network behaviour are only observable by
running the application. See [testing-strategy.md](testing-strategy.md) for where this sits in the
overall pyramid.

## Validation status

The **required** validation (group A below) has been completed successfully on a sandboxed Debug
build: the source and destination panels, access to a file outside the app container, source
integrity, absence of location disclosure, cancellation, re-selection, export and relaunch behaviour
all behaved as specified, with no sandbox, write, access or runtime errors. No network anomalies were
reported during that run; the **primary** offline guarantee remains the structural rule in
`Scripts/check-boundaries.sh` plus the absent network entitlement, with the dynamic observation
(group C) being supplementary. Per-run details — dates, tool versions, file names, paths and hashes —
stay out of the repository; only this durable statement lives here.

The **drag & drop** validation (group B) has also been completed successfully on a sandboxed build, with
**every mandatory case passing and no anomalies observed**: drops from several authorised locations,
from the initial state and over an existing report; whole-drop refusal for multiple items, folders and
non-local items; refusal during an in-flight inspection; instructive targeting feedback and its
accessibility; the previous report preserved on refusal and replaced after a valid drop; correct name
and extension in the report; the source unchanged; nothing remembered across launches; the panel and its
cancellation unaffected; and no sandbox or security-scope anomaly. The sources listed in step 23 —
iCloud files, aliases, symlinks, app bundles and Mail file promises — were **not** exercised and remain
open (ADR-0014).

The **accessibility** validation of the report surface, including the waveform, has been **partially**
completed on a sandboxed Debug build (change `add-waveform-visualization`, group 7). It was performed
once over the finished surface rather than twice over a moving one, which is why it was deferred from
`improve-report-presentation`.

**Performed and passing:** the waveform is exposed to VoiceOver as a **single** element whose composed
label states what the drawing is — an amplitude envelope of the whole file, with the number of channels
combined — and announces no characterisation of the audio; individual buckets are never announced. The
states the surface can show announce the state they display, an absent waveform included. Every meaning
the drawing carries is also available as text. The drawing, its centre line and the surrounding text
stay distinguishable from the report's background in **both** light and dark appearance. No colour
carries meaning on its own anywhere on the report: amplitude does not change colour, and no colour is
used to express anything about the audio. Read over the whole report, no internal identifier appears as
a value — no underscored code, enum case name, wire key or bare token. The type identifier and the
codec token do appear as **secondary detail** beneath their translated names, which is the accepted
behaviour of `improve-report-presentation` and exists so a readable summary never hides the exact datum.

**Not completed, and not to be cited as done:**

- **Accessibility text sizes**, over the waveform and over the whole report alike. The layout was
  reviewed at the normal text size and showed no clipping, overlap or lost controls — but the system's
  largest sizes were never exercised, because **macOS provides no way to exercise them for this
  application**. That is measured, not assumed: the preview canvas offers only colour-scheme variants
  for a macOS destination, and SwiftUI's dynamic-type modifier has no effect on macOS — the same text
  renders at an identical size from the default scale through the largest accessibility scale. macOS
  exposes no system-wide Dynamic Type for a SwiftUI application to adopt, so the criterion as written
  has no referent on this platform. Following this project's own rule — *a criterion that cannot be
  evaluated is recorded as not evaluated, never as passed* — it is recorded here as **not evaluable as
  written**, pending a decision on whether to reword it to what the platform can exercise. This covers
  the inherited check `improve-report-presentation` 9.3 / 7.4, which therefore also remains open.
- **The VoiceOver traversal of the whole report — a known gap, pending investigation.** Accessibility
  Inspector reads the tree correctly, including the waveform's composed label, but an inspected tree is
  not a walked one: across several passes, interactive VoiceOver reached only the export action and the
  file-picking action — the two focusable controls, which are exactly what lies outside the report's
  scrolling area — and would not enter the report's contents. The properties, warnings and status were
  therefore never observed being read aloud, and the reading order was never confirmed. **Recorded as a
  failure rather than as an omission.** One candidate cause was tested and ruled out: declaring the
  report's content an accessibility container changed nothing, and was reverted rather than kept.
  Whether the remainder is a defect in the surface or a property of the testing environment is **not
  established**, and diagnosing it belongs to a dedicated accessibility change rather than to the
  waveform slice, which did not introduce the behaviour. This is the inherited check
  `improve-report-presentation` 9.2, still open.

The inherited check `improve-report-presentation` 9.1 (no internal identifier on screen) and 9.4 (no
meaning carried by colour alone) **were** performed, and are recorded above.

The **spectrogram's** manual validation (change `add-static-spectrogram-visualization`, group 10) was
**deliberately deferred**, and the section below states exactly what that leaves standing and what it
does not.

The **true peak's** validation (change `add-true-peak-measurement`, task 10.2) **passed** on a
confirmed-fresh instance launched by executable path, on an analytic fixture whose waveform crosses full
scale **between** samples: *Peak sample* −1.43 dBFS, *Clipped samples* 0 and *True peak* +1.58 dBTP were
seen together, with no warning or diagnosis attached, and the exported document carried the value
linearly. The section at the end of this document records it, including that VoiceOver was not
exercised.

The **shared PCM read's** validation (change `add-shared-pcm-read`, task 5.2) **passed** on a
confirmed-fresh instance over two real files, one uncompressed and one compressed: report, waveform,
spectrogram and signal levels all present and unchanged, the replacement of one file by another clean,
and nothing perceptibly slower. The section at the end of this document records it, including one
cosmetic axis-label defect that predates the change.

Re-run this runbook whenever the selection, drag & drop, export, routing, sandbox or entitlement
behaviour changes.

## The spectrogram's manual validation — deferred by product decision (2026-08-07)

The exhaustive manual pass over the static spectrogram was **not executed**. This is a product decision
to defer, taken with the surface finished and working, not an omission and not a failure. It is recorded
here because the alternative — leaving it unsaid — would let a later reader assume the checks were made.

**The performance regression that had blocked this validation is fixed.** The first attempt at this pass,
on 2026-08-07, stopped at its first step: a real file took tens of seconds to draw. That was diagnosed,
corrected, and the correction was verified by running the application — the same real FLAC that had been
watched taking about thirty-three seconds now shows its spectrogram in a few seconds. The reason the pass
was blocked no longer exists.

### OBSERVED

A basic functional check of the built application, and nothing more:

- the spectrogram works in the real application;
- the practical performance is substantially better, and the file that previously blocked this pass now
  draws in a few seconds rather than tens of them;
- the overall visual result and the revised colour ramp look satisfactory at first sight.

### NOT EXECUTED

The whole of group 10's literal battery — tasks **10.1 to 10.6**:

- **10.1** the VoiceOver announcement and the accessibility tree;
- **10.2** every meaning having a textual alternative, across all of the surface's states;
- **10.3** contrast in light and dark appearance;
- **10.4** the colour ramp viewed in greyscale;
- **10.5** the 96 kHz and 192 kHz files and how their empty upper range reads;
- **10.6** the by-eye sweep for a named encoder, a bitrate or a verdict.

The fixtures and the step-by-step runbook prepared for this pass exist and were left in place, outside
the repository; nothing has to be rebuilt to run it later.

### What this record does and does not claim

**A satisfactory first impression is not evidence that a criterion was met.** None of 10.1–10.6 is
recorded as passed, and none may be cited as passed. They were not run.

In particular, the absence of a visible defect is **not** a result for any of them: 10.4 asks for the
ramp to be *looked at* in greyscale and no one has looked; 10.5 asks whether a mostly-empty upper range
reads as information rather than as a drawing fault, which is a judgement no test makes; 10.1's tree was
never opened. Some of these are partly covered by automated tests — luminance monotonicity is asserted
every 0.25 dB, the axes are asserted to span the file's own Nyquist without cropping, and the ramp is
asserted to carry no verdict — but the tasks as written ask for **observation**, and a test is not an
observation.

The **known VoiceOver traversal gap** recorded above, from the waveform slice, is unchanged and still
open. It is carried forward as it stands; the spectrogram's 10.1 was not run at all, so nothing new is
known about it either way.

**Consequences, so they are not discovered later.** Group 10's tasks 10.1–10.7 stay open. Task 1.4 of the
same change forbids moving **ADR-0016** out of `Proposed` before this validation is done, so ADR-0016
remains `Proposed`; **ADR-0015** is independent and remains `Proposed` on its own separate criteria.
Group 11's task 11.4 — deleting `Spike/validate-static-spectrogram/` — is gated on ADR-0016 being
Accepted and therefore cannot be reached from here.

### A real manual pass, in part (2026-08-08)

A person ran part of group 10's battery against the real application. Recorded exactly as observed,
neither softened nor extended:

- **10.3 (contrast, light/dark): PASS.** The drawing, legend and surrounding text stay legible in both
  appearances.
- **Continuous resize: PASS**, though this is not a numbered task on its own — no flicker, no visible
  regeneration, and the spectrogram itself does not change while the window is resized. Corroborates
  group 12's move to a raster that is a function of the model rather than the view's size.
- **10.4 (greyscale monotonicity): FAIL.** Viewed in greyscale, the intensity stops being distinguishable
  with enough clarity. This is recorded as a real, observed defect — not as "not evaluated" — even though
  luminance is asserted strictly monotonic every 0.25 dB by automated test: a test proving the numbers
  increase is not the same claim as a person being able to tell adjacent levels apart by eye, and the two
  disagree here.
- **10.1 (VoiceOver / accessibility tree): not executed**, for the same reason as the comparison surface
  below — the environment did not grant this session's process Screen Recording or Automation access.
- **10.2, 10.5, 10.6: not addressed by this pass** and stay exactly as before — not evaluated, not
  claimed either way.

**This does not change 10.1, 10.2, 10.5 or 10.6's status**, which stay open exactly as recorded above.
**10.3 is now satisfied** by real observation. **10.4 moves from "not evaluated" to "evaluated and
failed"** — a stronger, more specific piece of information than the gap it replaces, and a real product
defect rather than a validation debt. Neither ADR-0016 nor group 11 is touched by this entry; that
decision belongs to whoever picks up this specific defect.

## The two-file technical comparison's manual validation — blocked by environment permissions (2026-08-08)

Change `add-two-file-technical-comparison`, group 7. **No item of group 7 is recorded as passed by
observation.** The attempt is recorded here so a later reader does not have to repeat the same blocked
path before finding a working one.

### What was prepared

Four real fixtures were generated with `AVFoundation` (the same technique `AudioFixtureSupport.swift`
uses for tests) for the minimum set of scenarios: `a.wav` (44.1 kHz/16-bit PCM, the primary file and its
own second file for the SAME case), `b.aiff` (48 kHz/16-bit PCM, big-endian — a clear DIFFERENT case),
`c.m4a` (AAC — lossy, so bit depth reads INCOMPARABLE against either PCM file, and doubles as the file to
replace B with), and `broken.wav` (a `.wav` extension over bytes that are not a WAV file, to fail a
second inspection outright). None of these entered the repository.

The real app was built and run: `xcodebuild -project App/AudioInspector.xcodeproj -scheme AudioInspector
-configuration Debug -destination 'platform=macOS' build`, then launched from
`DerivedData/.../Debug/AudioInspector.app`. `System Events` could see the running process, so the app
itself launched correctly.

### What blocked the pass

Two separate macOS permissions, neither grantable by this session itself (see this project's own rule:
modifying security/privacy settings is not something to do unattended), stopped every subsequent step:

- **Screen Recording** — `screencapture` failed with `could not create image from display` for the
  process hosting this session, before and after the permission was added and the host app restarted.
  No screenshot of the running app was obtained.
- **Accessibility** — `osascript`/`System Events` failed with *"osascript no tiene permitido el acceso de
  ayuda"* (error -1719) on anything beyond listing process names — reading the window's accessibility
  tree, clicking a button, or sending a keystroke were all refused. No UI scripting, and therefore no
  driving of the file picker, no click on *Compare with another file…*, and no VoiceOver interaction, was
  possible.

Both were tried again after the permission was granted and the host app was restarted, with no change.
Diagnosing further (a different TCC identity than the one granted, a process that cannot self-inspect its
own permission state, or something else) was not pursued past this point, in keeping with this pass's
own instruction not to turn an environment limitation into an investigation.

### What stands in for observation, and its limit

With no way to drive or photograph the running app, group 7 falls back to what the source and the
existing test suite can show — which is real evidence, but is not the observation the tasks ask for:

- **7.1** (each row announced as one element) is true **by construction**: every comparison row in
  `ComparisonView.comparedRows` carries `.accessibilityElement(children: .ignore)` plus a single
  `.accessibilityLabel(row.accessibilityLabel)`, a standard SwiftUI mechanism whose behaviour does not
  vary at runtime. `ComparisonPresentationTests` pins the label's exact text — property, both files'
  values, then the outcome, with the incomparable reason included — for a normal row and an incomparable
  one. What is missing is a live reading of the rendered tree confirming this app, today, exposes what
  the modifier promises; unlike the waveform's own validation (above), which recorded this as directly
  observed, this one could not be.
- **7.2** (no meaning carried by colour, position or a symbol alone) is supported by a source read: every
  `ComparisonOutcomeDisplay` case carries real text (`Same`, `Different`, or the stated reason), the only
  colour distinction is `.secondary` vs `.primary` on already-worded text (never a bespoke hue standing
  for a meaning), and no icon or symbol appears anywhere in `ComparisonView`. Actual contrast and legibility
  were not seen.
- **7.3** (legible in light and dark) has no automated substitute and was not evaluated at all — this one
  is purely visual and the blocked permissions removed the only way to check it.
- **7.4** (an eye-read for a preferred file, a verdict, a score, an unread encoder or bitrate) is
  substituted by `ComparisonPresentationTests.noOutcomeUsesForbiddenWording`, which scans every one of the
  25 reachable state pairings plus the fixed copy against a forbidden-word list, and by a source-literal
  scan of every string in `ComparisonPresentation.swift`, `ComparisonView.swift` and the comparison
  controls in `RootView.swift` against a second list (`recommended`, `original`, `source`, `derived`,
  `fake`, `transcode`, `winner`, `loser`, `same file`, `identical file`, and others) — clean. This is
  exhaustive over everything the vocabulary *can* render, which is stronger than a sampled by-eye pass,
  but it is a string scan, not the eye-read the task names.
- **7.5** is satisfied by this section: the result is recorded plainly, including everything that was
  not checked.

**Consequence.** Per this task list's own rule — "nothing below may be marked done without actually
performing it" — 7.1 through 7.4 stay open. Only 7.5 is marked done. ADR-0017 stays `Proposed`: its own
promotion criterion names a person having looked at the surface, which did not happen here.

### Re-running this pass

Grant both **Screen Recording** and **Accessibility** to the process that will run the shell commands
(System Settings → Privacy & Security), confirm with `screencapture` and
`osascript -e 'tell application "System Events" to tell process "AudioInspector" to get entire contents
of window 1'` that both succeed, then rebuild the app and repeat: SAME (`a.wav` against itself),
DIFFERENT (`a.wav` vs `b.aiff`), INCOMPARABLE (`a.wav` vs `c.m4a`, bit depth), FAILED (`broken.wav`),
replace B→C, close, light/dark, narrow/wide window, Accessibility Inspector on one row of each kind, and
an interactive VoiceOver traversal. The known VoiceOver traversal gap recorded above (the report's own
content not reached by interactive VoiceOver) was never re-checked here and its status against the
comparison section is therefore also unknown.

### Retry (2026-08-08, same day) — still blocked, and why this is not recorded as NOT EVALUABLE

Before repeating the whole pass, the two capabilities above were checked again, on their own, with
nothing rebuilt or relaunched: a single `screencapture` and a single minimal `osascript` call to `System
Events`. Both failed again:

- `screencapture -x <file>` → `could not create image from display`, unchanged from before.
- `osascript -e 'tell application "System Events" to get name of every process whose name contains
  "AudioInspector"'` → **a different, more specific error than last time**:
  *"No tienes autorización para enviar eventos Apple a System Events"* (-1743). A bare
  `tell application "System Events" to return "ping"` succeeds, so the process can address System Events
  at all; what it cannot do is direct System Events to inspect or control another application. That is
  **Automation** (System Settings → Privacy & Security → Automation → *this session's host process* →
  System Events), a third, separate permission from both Screen Recording and the general Accessibility
  toggle named in the first attempt.

Per the instruction for this pass, this was checked once more and not pursued further — no third
permission was requested mid-session, and no attempt was made to launch the app again with no way to
observe it.

**This is deliberately not filed as NOT EVALUABLE.** This document uses that label for a criterion with
*no referent on this platform* (the Dynamic Type case above) or a repeatedly-attempted, real interaction
that a properly-permissioned run could not get past (the waveform's VoiceOver traversal gap). Neither
applies here: a human, or a session holding the ordinary permissions any Mac user grants an app once,
could complete every one of 7.1–7.4 in minutes. What is missing is not a capability of the platform but
an entitlement of the process running this pass, and it has now failed to appear across two separate
attempts, one of them after being explicitly granted and the host restarted. Recording that as
"unobservable" would misstate a mundane, fixable gap as a platform limit, which is exactly the confusion
this document's own convention exists to prevent. **7.1–7.4 therefore stay open as ordinary unfinished
work, not as a permanent or platform-level limitation.**

**What was decided instead of re-attempting the permissions a third time**, reading each task's literal
text against this repository's own precedent (the near-identical spectrogram tasks 10.2 and 10.6 stayed
open despite comparable automated coverage, on the stated ground that "a test is not an observation"):

- **7.1**, **7.2**, **7.3** and **7.4** all name the rendered, running surface — "announced," "remains
  legible," "read... by eye" — not the source that produces it. None is closed by the structural audit
  and the exhaustive wording scan already on record (in `ComparisonPresentationTests` and in this
  document's earlier section); that evidence is real but is, consistently with the spectrogram's own
  precedent, not treated as a substitute for looking. All four stay open, unchanged from the first
  attempt.
- **6.12** is a different kind of task — a structural audit of the domain and presentation *types*, not
  of the rendered surface — and is closed separately, in `tasks.md`, on the strength of a completed
  review of the full public surface of `PropertyComparison`, `ComparisonGap`, `FileComparison`,
  `ComparisonRowDisplay`, `ComparisonFormatter` and `ComparisonView`: no accessor anywhere returns a
  preferred side. See that task for the exact wording.
- Group 8's tasks 8.1–8.3 (the four gates, the diff's scope, the domain's isolation) do not depend on
  7.1–7.4 at all and could run today; **8.4 does** — deciding ADR-0017's status from 1.5 and archiving —
  because ADR-0017's own Status line requires "a person looking at it," which "partial evidence does not
  promote." That has not happened, so **the change is not ready to close**, independent of whether its
  mechanical gates would pass.

### Concluded (2026-08-08): deferred by decision, not resolved

A third, single-purpose check of the same two permissions — done immediately before this entry, before
touching the app again — produced the same result as the first two: `screencapture` still cannot create
an image from the display, and `System Events` still refuses to inspect or control another application
on this session's behalf (Automation). No fourth attempt was made: the block is now treated as settled
rather than as something to keep re-checking.

**What is true, stated once and plainly:**

- The implementation is finished against production code, and its architecture is closed: nothing in
  `Sources/AudioInspectorDomain` gained a framework import or a port, the JSON exporter is
  byte-identical, and the whole automated matrix (group 6, including 6.12's structural audit) is
  complete.
- **No defect of the product was observed at any point**, in three separate attempts, because none of
  the attempts got far enough to observe the product at all — the block sits entirely upstream of the
  running app.
- The manual observation itself — a person actually looking at the rendered surface, in light and dark,
  with Accessibility Inspector and VoiceOver — **did not happen** and is not claimed to have happened.

**This is recorded exactly as `add-static-spectrogram-visualization` records its own group 10**: deferred
by decision, nothing marked, the debt named rather than hidden. Per that same change's own precedent, a
deferred validation does not promote the ADR it gates (ADR-0016 stays `Proposed` there for the identical
reason) and does not close the task that bundles "decide the ADR's status and archive" (its 11.5 stays
unchecked, exactly as 8.4 stays unchecked here). Nothing in this document, in `tasks.md`, or in
ADR-0017 has been reworded to change that outcome — the criteria that were true before this attempt are
still true after it. The debt is a **deferred human observation**, prepared and ready to run whenever the
two permissions above are granted to whatever process attempts it next; it is not evidence of a problem
with the comparison itself.

### A real manual pass, in part (2026-08-08)

A person ran the comparison against the real application with the prepared fixtures, replacing part of
the block above rather than the whole of it. Recorded exactly as reported.

**Case 1 — the same FLAC compared against itself.** Every comparable property read `Same`; no difference
was invented; the extension/size/status context row stayed uncompared, as it always does; no forbidden
word appeared (`better`, `worse`, `winner`, `loser`, `original`, `copy`, `source`, `derived`, `fake`,
`transcode`, or similar).

**Case 2 — two distinct FLAC files.** `Different` appeared where the files actually differ (duration);
`Same` appeared where they agree (sample rate, codec, and others); `Not comparable` appeared where
neither is a fact the other can be measured against; the section's own subtitle still stated, unchanged,
that the comparison does not say which file is better or whether the two hold the same recording.

**Case 3 — a second file that is not really audio (a `.js` file renamed to `.wav`).** The first report
stayed intact; the second correctly showed that it could not be inspected; the comparison kept rendering
around that failure rather than breaking; no invented state like *"Comparison failed"* appeared — the
second file's own failure is what is shown, exactly as `ComparisonCopy.failedHeadline` and the flow's own
tests already specify; no crash, no visible inconsistency.

**Flow.** The first report stayed visible throughout; choosing another second file replaced the
comparison correctly; *Close comparison* removed only the comparison; a new comparison could be started
again afterward; no visual defect was observed at any point.

**What this closes, and on what literal ground:**

- **7.2** ("every meaning has a textual alternative; nothing depends on colour, position or a symbol") is
  now satisfied by real observation: every meaning the surface produced in these three cases — same,
  different, not comparable, and a second file's own failure — was read as words, not inferred from a
  colour or a symbol. Closed.
- **7.4** ("read the whole surface by eye and confirm nothing names a preferred file, a verdict, a score,
  an encoder or a bitrate the app did not read") is now satisfied: the whole surface was read by eye
  across three real, distinct states plus the replace/close flow, and none of the named claims appeared;
  the denial sentence in the subtitle was confirmed present and unchanged. Closed.

**What stays open, and exactly why — nothing in the new evidence touches these:**

- **7.1** ("each property row is announced as a single element... " — an accessibility-tree/VoiceOver
  claim) — no Accessibility Inspector or VoiceOver observation of the comparison surface was performed or
  reported. The three cases above are visual/functional observations, not accessibility observations, and
  do not stand in for one. **Still open.**
- **7.3** ("the surface remains legible in light and dark appearance") — light and dark were checked for
  the **spectrogram** in this same pass, not for the comparison surface; no light/dark observation of the
  comparison was reported. **Still open**, for a different reason than 7.1: not contradicted, simply not
  yet looked at.

**Consequence for ADR-0017.** Two of four criteria under group 7 are now real; two are not. The ADR's own
Status line says "validated with a person looking at it. Partial evidence does not promote it." — and two
open criteria out of four is exactly partial evidence, however much stronger than before. **ADR-0017
stays `Proposed`.** 8.4 stays open for the same reason, unchanged: it still needs the decision this
remaining gap prevents. Nothing in the ADR, `tasks.md`, or this document has been reworded to close that
gap; only what was actually observed has been recorded.

### A second real pass closes light/dark and attempts VoiceOver (2026-08-08)

The same person returned to close the gap the first pass explicitly left standing.

**Light and dark: PASS.** The comparison itself — not only the spectrogram — was viewed in both
appearances and reported legible in both: rows, values, the outcome column, secondary text and the
*Compare with another file…* / *Close comparison* controls.

**Resize: PASS.** Reported correct, consistent with the first pass's report for the spectrogram and with
this surface using the same `Grid`-based layout throughout.

**VoiceOver: attempted, and it reproduced this project's own known accessibility gap rather than
observing anything new.** Recorded exactly as reported:

> VoiceOver validation attempted. Existing accessibility issue reproduced unchanged (focus remains
> trapped on *Export JSON*). No evidence that the comparison UI introduces a new accessibility
> regression.

This is not a new finding. It is the same **known VoiceOver traversal gap** recorded earlier in this
document for the report surface (the waveform slice): "interactive VoiceOver reached only the export
action and the file-picking action... and would not enter the report's contents." A comparison renders
*inside* that same report content, below the properties — so if VoiceOver's focus never gets past the two
controls outside the scrolling area, it was never going to reach a comparison row either, regardless of
anything this change does. That is exactly why there is no evidence of a *new* regression: the trap sits
upstream of anywhere this feature's own accessibility contract could be exercised.

**It is also, for the same reason, not evidence that the contract is met.** 7.1 asks whether a comparison
row announces as one element naming the property, both values and the outcome. VoiceOver never reached a
row, so that question was not answered either way — not "answered and fine despite the bug," but
genuinely unobserved. This project already has a precedent for exactly this situation: the identical gap
is why **ADR-0015 stays `Proposed`**, not an exception that let it promote. Applying that same standard
here rather than a new one: **7.1 stays open, and ADR-0017 stays `Proposed`** on the strength of one
remaining, unobserved criterion — not four.

**What this closes:** 7.3, on the light/dark evidence above. **What stays open, and why:** 7.1 — attempted
and blocked by a pre-existing, already-documented gap, not by anything new; tracked as the same debt, not
a fresh one. Nothing about 7.2 or 7.4, closed in the first pass, changes here.

## Signal level metrics — a real defect found by manual validation (2026-08-11)

Change `add-computed-technical-properties`, group 8/ADR-0018's own promotion criterion ("its own manual
validation is done"). A person ran the real Debug build against a real stereo WAV fixture (4 s, 44.1 kHz,
DC-biased differently per channel, a full-scale burst on channel 1) and reported both screenshots and
the exported JSON verbatim. **This pass found a real, reproducible defect, not merely "not yet run."**

### OBSERVED — the on-screen surface (PASS on every checked point)

- The **Signal levels** section appears, legible, directly beneath Waveform and before Spectrogram —
  exactly the placement group 5 decided on.
- **Peak sample**: `0.00 dBFS`, with `Channel 1: 0.00 dBFS · Channel 2: -8.64 dBFS`. In dBFS, as
  specified.
- **RMS level**: `-9.15 dBFS`, with per-channel values. In dBFS, as specified.
- **DC offset**: `+0.0055`, with `Channel 1: +0.0311 · Channel 2: -0.0200` — linear, signed, **not**
  dBFS, as specified.
- **Clipped samples**: `0`, with the explanatory line "Samples at or beyond full scale." An integer, as
  specified. (The fixture's intended clipped burst used raw `+32767`, which normalizes to `0.999969…`
  under the standard 16-bit-PCM-to-float convention (division by `32768`, not `32767`) — **not** `≥ 1.0`.
  This is the fixture's own construction error, not a finding about the reader: it is consistent with,
  and confirms, correct `≥ 1.0` threshold behaviour rather than contradicting it.)
- Channels are labelled **"Channel 1" / "Channel 2"** — never "Left"/"Right", as specified.
- No quality or diagnostic wording was seen anywhere in the section.
- **Waveform** and **Spectrogram** remained visible and intact, both showing the transient from the
  fixture's loud burst; neither was disturbed by Signal levels being present.
- The rest of the report (Format, Encoding, Notes, Result, File) read normally, with
  `averageFileBitrate` shown under its own label ("Average file bitrate 1,411.29 kbps") distinct from
  `Declared bitrate`/`Estimated bitrate`, each correctly reflecting this WAV's own real absence/
  unreliability.

### OBSERVED — the exported JSON (FAIL, reproduced twice)

Exported twice, several minutes apart, **after** the Signal levels values were already visible on
screen (confirmed explicitly by the person running the pass, ruling out a load-in-progress race):
`generatedAt` `2026-08-11T00:17:09Z` and, on request, again at `2026-08-11T00:24:17Z`. **Both documents
are structurally identical and both omit `measurements` entirely** — `schemaVersion`, `generatedAt`,
`generator`, `inspectedFile`, `inspectionStatus`, `technicalProperties` (including
`averageFileBitrate`, correctly present under its own key) and `warnings` are all present and correct;
`measurements.signalLevels` never appears, in either export.

**This is a real defect, not the expected "absent when nothing to report" case**: the UI had already
rendered real, non-`loading` signal level metrics in both cases, so the export's own contract
(`ReportView`'s `exportableSignalLevelMetrics` collapsing only `loading`/`absent`/`failed`/`cancelled`
to `nil`) should have produced a populated `measurements` object.

**Where this sits relative to existing coverage.** Every automated test that exercises
`SignalLevelMetrics` reaching the export layer (`JSONReportExportMeasurementsTests`) constructs a
`SignalLevelMetrics` fixture directly and hands it straight to the exporter — none of them go through
`ReportView`'s real `Button`/`.toolbar` action. `EndToEndFlowTests`, the suite that does exercise the
real `ReportExportCoordinator` end to end, calls `exportModel.export(report, signalLevelMetrics: nil)`
explicitly in all three of its export scenarios. **No test in this repository exercises the actual path
from `ReportView`'s export button through to a populated `measurements` object.** That gap is exactly
what this manual pass was for, and it found a real defect the automated suite structurally cannot see.

**A hypothesis, recorded as a hypothesis, not a finding.** `exportAction` (and its `Button`) is nested
inside a SwiftUI `.toolbar { ToolbarItem(placement: .primaryAction) { exportAction } }` modifier
(`ReportView.swift`). On macOS, a `.toolbar` item's underlying `NSToolbarItem` is not guaranteed to be
rebuilt on every `body` re-evaluation the way in-line content is — if it is not, a closure captured on
the toolbar item's first construction (while `signalLevelMetrics` was still `.loading`, hence `nil`)
would explain a button that always exports `nil` regardless of what the rest of the view now shows,
consistent with both reproductions. This was **not confirmed by live debugging** (breakpoints,
logging) — this pass was limited to build, launch, and observe, per its own scope — so it is recorded
as the strongest available lead, not as a diagnosis.

### Consequence

**This is filed as a found defect, not as "validation not yet done."** No code was changed to
investigate or fix it, per this pass's own instruction. **ADR-0018 stays `Proposed`**: its own
promotion criterion required this change's manual validation to be done, and it has now been done —
but it did not pass. Group 8's task 8.3 stays open for the ADR decision it depends on; `openspec
archive` was never going to run in this session regardless. The next session on this change should
start by reproducing this defect under a debugger (or by testing `ReportView`'s export button through
`ViewInspector`/a UI test, if this project ever adopts one) before attempting a fix — printing the
value of `exportableSignalLevelMetrics` at the moment the closure executes would confirm or rule out
the toolbar hypothesis directly.

## Signal level metrics — resolved: a stale app instance, not a code defect (2026-08-11, later same day)

The next session did exactly what the entry above asked: reproduced the defect under live
instrumentation before touching production logic. **It found no code defect at all.** The record above
is kept verbatim, unedited, because what was actually observed (JSON without `measurements`, twice) was
real — the diagnosis of *why* was wrong, and this section is the correction, not a retraction.

### What the instrumentation showed

Temporary, minimal `print()` tracing was added at every seam named in the earlier "next session" note —
`RootView.reportSurface`, `ReportView.body`, the export button's own closure, `ReportExportModel.export`,
`AppContainer`'s export closure, `ReportExportCoordinator.export`, and `JSONReportExporter.export` — then
the real Debug binary was launched **directly from its executable path**, not via `open`, specifically to
control which process instance was being driven. A person repeated the exact same flow (drop the fixture,
wait for Signal levels to show real values, click *Export JSON…*, complete the save panel).

**The full captured trace, values elided for brevity, all showing the real `SignalLevelMetrics` — never
`nil` — at every single step:**

```
RootView.reportSurface built. presentation.signalLevelMetrics=loading            (× while loading)
RootView.reportSurface built. presentation.signalLevelMetrics=available(...)     (once settled)
ReportView.body evaluated. signalLevelMetrics=metrics(...)
ReportView button tapped. signalLevelMetrics=metrics(...), exportableSignalLevelMetrics=Optional(...)
ReportExportModel.export received signalLevelMetrics=Optional(...)
AppContainer export closure received signalLevelMetrics=Optional(...)
ReportExportCoordinator.export received signalLevelMetrics=Optional(...)
JSONReportExporter.export received signalLevelMetrics=Optional(...)
```

Every seam in the chain — including the `Button` inside `.toolbar { ToolbarItem(...) }` that the earlier
hypothesis suspected — captured and forwarded the current, real value. **The toolbar hypothesis is
false**, disconfirmed directly rather than left unconfirmed. All instrumentation was reverted in full
immediately after (`git diff` against the pre-instrumentation commit showed no residue); none of it was
committed.

### The actual explanation

While instrumenting, a second, much older `AudioInspector` process (PID observed as `48716`, launched
hours earlier, carrying `-NSDocumentRevisionsDebugMode YES` — the flag Xcode adds when a build is run via
its own Run button) was found still alive in the background, and could not be terminated with `kill -9`
from this session (no `sudo`; the process was likely still attached to Xcode's debugger). **`open` on
macOS activates an already-running instance of an app rather than launching a new one.** The earlier
manual-validation session (the entry above) used `open "<path>/AudioInspector.app"` to launch the build —
which, given that stale process was already running, most likely brought *that* old instance to the
front instead of starting the freshly built one. Whether that old instance predated the `measurements`
export capability entirely, or carried some other now-irrelevant stale state, was not established and
does not need to be: either way, **the build under test was not the build that was actually running.**

This was not asserted from theory — it was designed around: this session killed every reachable
`AudioInspector` process, rebuilt clean, and launched the new binary **by its executable path directly**
(never `open`), confirming a distinct PID each time and confirming with the person running the pass that
the window on screen was a fresh, empty import screen before proceeding.

### Real validation, on a confirmed-fresh instance, reproduced twice

With process identity no longer in doubt, the full Fase 10 checklist was repeated against the same
fixture, twice, several seconds apart (`generatedAt` `2026-08-11T11:52:32Z` and
`2026-08-11T11:52:55Z`), and the **complete exported JSON was read directly**, not summarized secondhand:

- `schemaVersion`: `1`. ✅
- `technicalProperties.averageFileBitrate`: present, `state: "uncertain"`, `value: 1411288`,
  its own `reason`. ✅
- `measurements` and `measurements.signalLevels`: **present in both exports.** ✅
- `overall`: `{"clippedSampleCount":0,"dcOffset":0.005549694411456585,"peakSample":0.999969482421875,
  "rms":0.34888744354248047}`. ✅
- `channels`: two entries, each with its own `sampleCount`/`peakSample`/`rms`/`dcOffset`/
  `clippedSampleCount`, matching the on-screen per-channel values from the original pass exactly
  (`0.9999695`/`0.42638656`/`0.031098228` and `0.3699646`/`0.2482728`/`-0.019998841`). ✅
- **Linear values, never dBFS**: `peakSample: 0.999969482421875`, not `"0.00 dBFS"` — confirms the wire
  contract holds even though the same number reads as `0.00 dBFS` on screen. ✅
- `clippedSampleCount`: plain integer (`0`), both overall and per channel. ✅
- No absolute path, `file://` URL, or any other filesystem detail anywhere in either document. ✅
- No `loading`/`unavailable`/`failed`/`cancelled` — only the real, settled measurement. ✅
- **Reproducible**: both exports are structurally and numerically identical, differing only in
  `generatedAt`.

### Consequence

**This closes the defect record above as resolved-not-a-defect.** No production code was changed — the
capability was correct throughout; only the earlier *test methodology* (launching via `open` against an
environment with a stale, unkillable process already running) produced a false negative. One thing *was*
added: `EndToEndFlowTests.theRealSignalLevelMetricsPathReachesTheExportedDocument`, a new automated test
that walks the real production sequence (real file → real decode → real `SignalLevelMetricsGeneration` →
`InspectionPresentation.signalLevelMetrics` → the same `.metrics`-unwrapping extraction
`ReportView.exportableSignalLevelMetrics` performs → real export) and asserts `measurements.signalLevels`
reaches the document. It passes on the current code without any change, but it closes the actual gap this
whole investigation started from: **no automated test previously drove this path with real, non-`nil`
metrics** — every existing one passed `nil` explicitly or handed a hand-built fixture straight to the
exporter, skipping the seam where the false defect appeared to live. A negative control (temporarily
re-capturing `nil` inside the new test) confirmed the test fails when the value is actually lost, then was
fully reverted.

**ADR-0018's manual-validation criterion is now genuinely satisfied**: a person looked at the real
running application, confirmed the on-screen surface (already recorded above), and confirmed the real
exported JSON, twice, reproducibly, on a build whose identity was verified rather than assumed.

## What is already automated (do not re-verify by hand)

These are covered by `swift test` / `Scripts/check-boundaries.sh` and need no manual work:

- the whole chain fixture → reference → reader → use case → report → JSON written to disk, and the
  coherence between the report, its presentation and the exported document (`EndToEndFlowTests`);
- the source file is byte-identical (SHA-256), same size and same modification date after inspecting
  **and** exporting (`EndToEndFlowTests`);
- no networking framework or API in production code (`check-boundaries.sh`, rule 9);
- the entitlements declare App Sandbox and `user-selected.read-write`, and declare **no** network or
  broad-folder capability (`OfflineConfigurationTests`).

## What only a human can validate

Split into two groups, because they carry different weight.

**A. Required — sandbox and panels.** The app must actually work under the sandbox with real panels.
**B. Additional — dynamic network observation.** Evidence that no traffic occurs at runtime. The
configuration guarantee above already means the OS would refuse a connection; this observation is
confirmation, not the primary guarantee.

## Prerequisites

- macOS 15 or later, Xcode 16 or later.
- A local audio file **outside** the app container — e.g. something in `~/Music`. Any format is
  acceptable; note which one you used. Do not use copyrighted material you cannot keep local.
- A writable folder outside the container for the export — e.g. `~/Desktop`.

## Procedure

### Setup

1. Open `App/AudioInspector.xcodeproj`.
2. Select the **AudioInspector** scheme and the **My Mac** destination.
3. Open the target's **Signing & Capabilities** tab and confirm:
   - **App Sandbox** is present;
   - **User Selected File** is set to **Read/Write**;
   - there is **no** Incoming/Outgoing Connections (network) capability;
   - there is no Downloads/Music/Pictures/Movies folder capability.
4. Build and run (⌘R). The window opens on the import screen.

### A. Required — sandbox, panels and the flow

5. **Cancel the source picker.** Click *Choose audio file…*, then dismiss the panel. Expected: no
   error is shown and the app stays exactly as it was.
6. **Inspect a file outside the container.** Click *Choose audio file…* and pick the file from
   `~/Music`. Expected: the report appears with the file's name, extension, size and modification
   date, the eight technical properties each showing a state, any warnings, and the global status.
7. **Check the report is honest.** Expected: no absolute path, no `file://` URL and no folder name
   anywhere on screen; the source line reads that the location is omitted; properties that could not
   be determined show their state (unavailable/unsupported/uncertain/failed) rather than a value.
8. **Re-select and cancel.** Click *Choose another file…*, then dismiss the panel. Expected: the
   progress screen appears while the panel is open and **the previous report comes back unchanged**
   once cancelled — no error.
9. **Re-select and complete.** Click *Choose another file…* and pick a different file. Expected: a
   new report replaces the previous one.
10. **Cancel the destination picker.** Click *Export JSON…*, then dismiss the save panel. Expected:
    no error, the report is untouched, and no file is written.
11. **Export outside the container.** Click *Export JSON…* and save to `~/Desktop`. Expected: the
    suggested name is `<file>-inspection.json`, the save succeeds, and the app reports success.
12. **Inspect the exported JSON.** Open it in a text editor. Expected: `"schemaVersion": 1`; a
    `generatedAt`, a `generator`, an `inspectedFile`, eight `technicalProperties`, `warnings` and an
    `inspectionStatus`; and **no** path, URL, bookmark, parent folder or internal identifier.
13. **Confirm the source did not change.** In Terminal, before and after the whole flow:
    `shasum -a 256 "<source file>"` and `stat -f "%z %Sm" "<source file>"`. Expected: identical hash,
    size and modification date. (Run the "before" reading prior to step 6.)
14. **Confirm nothing is remembered.** Quit the app and launch it again. Expected: it starts on the
    import screen with no recent file and no restored report — there is no bookmark and no
    persistence.

### B. Required — drag & drop (change `add-drag-and-drop-file-import`)

The temporary spike already observed how Finder delivers a dropped URL under the sandbox: conventional
path URLs, no file-reference form, `startAccessingSecurityScopedResource()` returning `false` with the
file still readable, and access surviving the hop into async work (ADR-0014). **Those observations were
made against throwaway instrumentation, so they must be repeated against the real implementation**, and
the cases the spike did not reach are listed at the end.

15. **Drop from Desktop, from Music, and from a location outside the container** (an external volume or
    another folder you have not opened before). Expected each time: the inspection starts immediately
    and the report shows the file's real name and extension — the proof that no normalisation is needed.
16. **Drop onto the initial screen** and, separately, **drop while a report is displayed.** Expected: the
    report surface is left while the inspection runs and the *new* report replaces the old one when it
    completes. The panel's `Choose another file…` behaves the same way; nothing changed there.
17. **Drop two files at once.** Expected: the whole drop is refused, no inspection starts, any report on
    screen stays, and the notice reads *"Drop one file at a time."* — and never names either file.
18. **Drop a folder**, and **drop a non-local item** (drag an image or a link from a web page). Expected:
    refused with *"That item cannot be inspected."*, no inspection, previous report intact.
19. **Drop while an inspection is running.** Expected: no second inspection starts and the notice reads
    *"Wait for the current inspection to finish."*
20. **Targeting feedback.** Drag a file over the window without releasing. Expected: a visible border and
    the text *"Drop one audio file"* — instructive, never claiming the dragged content is valid, and
    never conveyed by colour alone. With VoiceOver on, confirm the hint and any refusal notice are read
    aloud.
21. **Panel unchanged.** Repeat steps 6–12 with `Choose audio file…`, including cancelling the panel from
    a displayed report: the report must survive and no error may appear.
22. **Source integrity and no persistence.** Repeat steps 13 and 14 for a file that arrived by drop.
23. **Coverage the spike did not reach.** Drop, and record what happens for each: a downloaded iCloud
    file, an evicted iCloud file, an alias, a symlink, an `.app` bundle, and a Mail attachment (a file
    promise, which SwiftUI drag & drop does not support). Expected: each either inspects correctly or is
    refused with a visible message — **never a silent no-op and never a hang.** If any of them shows a
    wrong file name in the report, that is the file-reference URL case ADR-0014 leaves open, and it must
    be reported rather than worked around.

### C. Additional — dynamic network observation

24. With the app running, observe it for the duration of a full inspect-and-export cycle using either
    - Instruments → *Network*, attached to the AudioInspector process; or
    - `nettop -p $(pgrep -x AudioInspector)` in Terminal.
    Expected: no outgoing connections. Record what you observed, including "no traffic seen".

## Result template

Copy this block, fill it in, and attach it to the pull request or the task notes. Do not commit a
filled-in copy to this file: the runbook is durable, a specific run is not.

```text
Date:
macOS version:
Xcode version:
App build configuration:      Debug | Release
Audio format(s) tested:
Source file location:
Export destination:

Signing & Capabilities
  App Sandbox present:                    yes | no
  User Selected File = Read/Write:        yes | no
  No network capability:                  yes | no
  No broad folder capability:             yes | no

A. Required
  5.  Cancel source picker, no error:     pass | fail | not run
  6.  Inspect file outside container:     pass | fail | not run
  7.  No location shown on screen:        pass | fail | not run
  8.  Cancel re-selection, report kept:   pass | fail | not run
  9.  Re-selection replaces report:       pass | fail | not run
  10. Cancel destination picker:          pass | fail | not run
  11. Export outside container:           pass | fail | not run
  12. Exported JSON is v1 and location-free: pass | fail | not run
  13. Source hash/size/mtime unchanged:   pass | fail | not run
      hash before:
      hash after:
  14. Nothing remembered after relaunch:  pass | fail | not run

B. Additional
  15. Dynamic network observation:        no traffic | traffic seen | not run
      tool used:
      observation:

Anomalies / notes:
```

## Shared PCM read — passed on a confirmed-fresh instance (2026-08-12)

Change `add-shared-pcm-read`, task 5.2. The spectrogram and the signal level metrics now come from
**one** decode instead of two, so what had to be confirmed by eye is narrow: the product still behaves
exactly as it did, and nothing about sharing is visible in the surface.

### Process identity, given the trap this document already records

The stale-instance failure recorded above (2026-08-11) was designed around rather than hoped away. The
same unkillable process from that entry — PID `48716`, launched 2026-08-10 under Xcode's debugger — is
**still alive and still not terminable** from an unattended session (`kill -9` has no effect, and
`System Events` cannot see it, so it holds no window). Because `open` activates an existing instance,
it was not used: the freshly built Debug app was launched with **`open -n`**, which forces a new
instance, and the new PID was confirmed distinct, registered with LaunchServices under its own name,
and free of any crash report. The person running the pass confirmed the window on screen was the newly
launched one.

### What was validated, and against what

Two real files from the operator's own library — not generated fixtures:

| | file A | file B |
| --- | --- | --- |
| format | Linear PCM WAV, 44.1 kHz, 16-bit, stereo | FLAC, **64 kHz**, stereo |
| duration / size | 5:09 · 54.5 MB | 4:53 · 83.1 MB |

Neither path, nor any location, is recorded here; the app itself showed `Source — User-selected local
file (location omitted)` for both, which is the privacy behaviour this project requires.

### Observed — both files

- **Report.** Complete and normal on both. The WAV read 5 of 9 properties cleanly and the FLAC 4 of 9,
  each remaining property carrying its own note rather than disappearing — the availability and
  certainty model behaving exactly as before. Format, Encoding, Notes, Result and File sections all
  present.
- **Waveform.** Present and correct on both, drawn across the whole file, with its own caption. It
  still arrives on its own read, ahead of the two shared analyses.
- **Spectrogram.** Present and correct on both, and **its content did not change by being fed from a
  shared read**: the WAV spans 0–22.05 kHz and the FLAC 0–32 kHz, each the true Nyquist of its own
  sample rate, with the time axis running to the file's real duration.
- **Signal levels.** Present on both, with every metric and its per-channel breakdown, in unchanged
  wording: WAV `Peak 0.00 dBFS` (0.00 / −0.96), `RMS −19.43` (−19.41 / −19.45), `DC 0.0000`,
  `Clipped 4` (4 / 0); FLAC `Peak 0.00 dBFS` (0.00 / −2.67), `RMS −21.62` (−21.52 / −21.73),
  `DC 0.0000`, `Clipped 0`.
- **States.** No new error, no permanent loading, no empty section, no section overwriting another.

### Observed — replacing A with B

The FLAC was inspected **in the same window, immediately after the WAV**. All four sections changed to
the new file together — name, format line, waveform, spectrogram and signal levels — and **nothing from
the previous file reappeared afterwards**. Stale-result handling is unchanged by sharing, as designed.

### Progressive delivery

Confirmed by the person running the pass: the report appeared immediately and the visualisations
followed, and **nothing felt slower than before the change**. Recorded exactly at that strength — the
pass was not timed by hand, and it does not need to be: the timings are measured in the spike's §15
(report at 1.5–2.0 ms; one full decode's worth of work removed).

### One defect seen, and it is not this change's

On the 64 kHz FLAC, the spectrogram's frequency axis draws **`32 kHz` and `30 kHz` overlapping** at the
very top: the Nyquist label lands on a round tick. It is cosmetic, it lives in the spectrogram's
presentation (`FeatureAnalysis`), and this change touches no Feature target — the same overlap would
occur on `main`. It is recorded here rather than fixed, so closing this change does not quietly widen
it.

### Limits of this pass

- Two files, one machine, one appearance (dark). Light mode, window resizing and VoiceOver were not
  re-checked: this change adds **no new surface**, so nothing about the accessible tree or the layout
  is new to evaluate.
- The evidence is screenshots plus the observer's answers, not an instrumented recording; the ordering
  and timing claims above rest on the measurements in the spike's §15, not on this pass.

## True peak — passed, including the case the measurement exists for (2026-08-12)

Change `add-true-peak-measurement`, task 10.2, and the second half of **ADR-0019**'s own promotion
criterion. Recorded here because the first half — agreement with an independent meter — is evidence a
machine can gather, and this one is not.

### Process identity

Task 10.2 asks for an instance launched **by executable path, never `open`**, and that is what happened:
the app was rebuilt, every reachable `AudioInspector` process was stopped, and the freshly built binary
was started directly from
`…/Build/Products/Debug/AudioInspector.app/Contents/MacOS/AudioInspector`, confirming a new PID. The
unkillable process from 2026-08-10 that this document already blames for a false defect is **still
alive** and still cannot be terminated from an unattended session; it holds no window, and launching by
path is immune to it in a way `open` is not.

### The fixture, and why it is generated rather than chosen

A real music file would prove nothing in particular: whether its waveform crosses full scale between
samples is an accident of that master. The fixture is therefore **analytic** — a 10 s, 44.1 kHz, float
WAV of a tone at a quarter of the sample rate, shifted an eighth of a cycle so every stored sample lands
at `amplitude/√2`, with the second channel 6 dB below the first so the per-channel breakdown carries
information. Its continuous maximum is exactly its amplitude, which is what makes the expected answer
knowable in advance rather than merely plausible. It is generated, measured and deleted; no audio binary
enters the repository.

### What was observed on screen

| | Observed |
| --- | --- |
| Peak sample | **−1.43 dBFS** — below full scale |
| Clipped samples | **0** |
| True peak | **+1.58 dBTP** — above full scale |
| Per channel | `Channel 1: +1.58 dBTP · Channel 2: −4.44 dBTP` |
| Method | *"Estimated by reconstructing the waveform between the stored samples, at 8× oversampling with a polyphase FIR reconstruction filter."* |

**That row is the whole point of the measurement, seen rather than argued**: a file with no clipped
sample whatsoever, whose waveform nonetheless rises above full scale between the samples that were
stored. The two facts sit beside each other and neither is presented as a consequence of the other.

Also confirmed by eye: the report, waveform, signal levels, true peak and spectrogram all present, none
stuck loading and none blanking another; **no warning, no colour, no badge and no diagnosis** on a
positive value; no claim of conformance to any standard; and the section holding its layout in light,
dark and at different window sizes.

### The exported document

Exported from that same inspection and read in full. `schemaVersion` 1; `measurements.truePeak` beside
`measurements.signalLevels`; `overall` **1.1999318599700928** — linear, where the screen shows
`+1.58 dBTP`, which is exactly the separation the contract requires; channels linear with their frame
counts; `"method": {"filter": "polyphase_fir_v1", "oversamplingFactor": 8}`. No path, no URL, no
bookmark, no lifecycle state, and no warning invented by the measurement — the three warnings present
are pre-existing property-level ones about the container and the bitrates.

**Reproducibility** was checked in a stronger form than exporting twice from one session: the value in
the document is **bit-identical** to what an independent run of the same pipeline produced through a
separate harness, on the same file, in a different process.

### Limits of this pass

- One machine, one fixture class (smooth at its boundaries, 44.1 kHz).
- **VoiceOver was not exercised.** The known traversal gap recorded earlier in this document — interactive
  VoiceOver reaching only the export and file-picking actions, never the report's contents — is
  unchanged and untested here; this change adds a section to that same scrolling area, so it inherits the
  gap rather than fixing or worsening it. ADR-0019's criterion asks for a person looking at the surface,
  which happened; it does not ask for VoiceOver, and none is claimed.
- Screen Recording and Accessibility remain denied to the session that drove the build, so there is no
  screenshot and no scripted traversal — the observations above are a person's, reported back.

## Programme bandwidth — prepared, not executed (2026-08-20)

**Status: PREPARED. Nothing below has been observed.** Group 7 of
`add-significant-bandwidth-measurement` implemented the surface and pinned it with automated tests;
this section is the runbook for the pass that has not run. ADR-0023's third promotion condition — a
person looking at the surface — is **not** satisfied by anything here, and the record stays `Proposed`
until it is.

### Why this needs a person at all

Everything about the *number* is already automated, from the file to the string: group 6 validated the
measurement through the production path, and group 7's suites assert the exact rendered text, the
rounding rule at all five sample rates, the absence phrasing, and a forbidden-vocabulary sweep. What
`swift test` cannot answer is whether the section **reads** as a fact rather than as a judgement to a
person seeing it in place, at a real window size, in both appearances — which is precisely what
ADR-0023's condition asks.

### The fixtures, and what each must show

Regenerate with the production path itself rather than by hand; every figure below was computed
**before** the app was opened, by running each file through the real decoder, the shared read and the
composition root's mapping.

| # | file | production reading | displayed value | displayed resolution |
| --- | --- | --- | --- | --- |
| 1 | `01-programme-16k.wav` — 5 s, 48 kHz, stereo, comb to 16 kHz | 16 101.5625 Hz on a 23.4375 Hz grid | **16.1 kHz** | **23 Hz** |
| 2 | `02-programme-20k.wav` — same, comb to 20 kHz | 20 085.9375 Hz on a 23.4375 Hz grid | **20.1 kHz** | **23 Hz** |
| 3 | `03-silence.wav` — 5 s of digital silence | none | **"Not computable for this file."** | not shown |
| 4 | `04-programme-16k-plus-click.wav` — fixture 1 plus one full-scale click | 16 101.5625 Hz | **16.1 kHz** | **23 Hz** |
| 5 | `05-mp3-64k.mp3` — 5 s comb to 20 kHz at 44.1 kHz, encoded at 64 kbps | 16 790.1562 Hz on a 22.9688 Hz grid | **16.8 kHz** | **23 Hz** |

Fixture 4 is the one to look at hardest: **it must be indistinguishable from fixture 1.** That is the
property the whole design exists for, and the only way to see it fail on screen is to have both in
front of you. Fixture 5 must read as a plain number like the rest — nothing on screen may hint at how
the file was encoded, and the word "MP3" must not appear anywhere in the section.

### Checklist

Tick only what was seen. A skipped line is not a pass.

- [ ] **Section** — "Programme bandwidth" appears as its own section, after Integrated loudness and
      before the spectrogram.
- [ ] **Value** — fixtures 1, 2, 4, 5 show exactly the displayed value in the table above.
- [ ] **Resolution** — shown as its own row, "Analysis resolution — 23 Hz", with **no `±`** anywhere and
      no operator joining it to the value.
- [ ] **Copy** — the method line reads "The highest frequency this programme carries persistently,
      within 60 dB of its own strongest spectral level." and nothing else is added beside it.
- [ ] **Absence** — fixture 3 shows the report's own not-computable phrasing, and **no number at all**:
      not 0 Hz, not 24 kHz, not Nyquist.
- [ ] **No warnings** — no colour, badge, icon, bold or alarm on any fixture, including fixture 2 where
      the reading sits near the top of the band. Fixture 2 must look exactly like fixture 1.
- [ ] **The impulse control, by eye** — fixtures 1 and 4 are identical in every respect.
- [ ] **Light / dark / resize** — the section survives both appearances and a narrow window; the method
      line wraps rather than truncating or clipping.
- [ ] **A→B stale** — inspect fixture 1, then fixture 2 before the first finishes: the section must show
      fixture 2's value, never a mixture.
- [ ] **Forbidden vocabulary** — read every word on screen. No "upsampled", "transcoded", "codec",
      "cut-off", "lossy", "real"/"true" resolution, no quality word, no comparison with the file's
      declared sample rate.

### What a failure here would mean

A wrong *number* would contradict group 6 and is the less likely outcome. The failure this pass is
actually looking for is a **framing** one: the section reading as a verdict because of where it sits,
what surrounds it, or how the eye pairs it with the declared sample rate two sections down. That is a
presentation defect, and it is the reason the condition asks for a person rather than a test.
