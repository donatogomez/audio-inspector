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
- **The VoiceOver traversal of the whole report.** Accessibility Inspector reads the tree correctly,
  including the waveform's composed label, but an inspected tree is not a walked one: with interactive
  VoiceOver the traversal reached only the export action and the file-picking action — the two focusable
  controls — and would not enter the report's scrolling area. The properties, warnings and status were
  therefore never observed being read aloud, and the reading order was never confirmed. **This is
  recorded as a failure rather than as an omission, and may be a real defect in the accessible
  traversal.** It is the inherited check `improve-report-presentation` 9.2, still open.

The inherited check `improve-report-presentation` 9.1 (no internal identifier on screen) and 9.4 (no
meaning carried by colour alone) **were** performed, and are recorded above.

Re-run this runbook whenever the selection, drag & drop, export, routing, sandbox or entitlement
behaviour changes.

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
