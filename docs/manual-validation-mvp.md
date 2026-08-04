# MVP manual validation runbook

A **procedure**, not a result. Nothing here is pre-filled: run the steps against a real build and
record what actually happened in the template at the end.

This runbook exists because part of what the MVP promises **cannot** be proven from `swift test`. The
package tests run unsandboxed and never launch the `.app`, so code signing, the effective
entitlements, the powerbox, the native panels, and real network behaviour are only observable by
running the application. See [testing-strategy.md](testing-strategy.md) for where this sits in the
overall pyramid.

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

### B. Additional — dynamic network observation

15. With the app running, observe it for the duration of a full inspect-and-export cycle using either
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
