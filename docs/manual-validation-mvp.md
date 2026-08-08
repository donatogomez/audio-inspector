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
