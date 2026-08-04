# Implementation Tasks

Design only in this step — **no task below is implemented or checked.** Group 1 is the documentary
commit that opens the change; every other group is implementation work to be done on its own branch.
Each task is small, verifiable, maps to one logical commit, and contains nothing out of scope.

Group 2 deliberately comes before any routing code: its outcome decides whether URL normalisation is
needed at all and, if so, which layer owns it.

## 1. Decision record and OpenSpec contract

- [ ] 1.1 Write ADR-0014 (`docs/adr/0014-drag-and-drop-file-access.md`, status `Proposed`): panel and
      drag & drop as two mechanisms of one explicit user selection; entitlement unchanged; temporary
      access; no bookmarks or persistence; the same `SourceInspectionCoordinator`; `URL` and AppKit
      confined to `AudioInspectorApp`; whole-drop rejection for multi-item drops; why a copying
      `Transferable` representation is rejected; instructive-only targeting feedback as an API
      limitation; and its relationship to ADR-0010 and ADR-0013 **without modifying either**.
- [ ] 1.2 Add ADR-0014 to the index in `docs/adr/README.md`.
- [ ] 1.3 Create the change `add-drag-and-drop-file-import` with `proposal.md`, `design.md`, the
      `MODIFIED` delta on `audio-file-inspection`, and this task list. The promoted spec is not edited
      directly.
- [ ] 1.4 `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` green.

## 2. Observe the URL a dropped file actually delivers (manual, sandboxed)

Blocks tasks 3 and 5. `swift test` cannot reach any of this: the package runs unsandboxed and unsigned
(`docs/testing-strategy.md`).

- [ ] 2.1 Build a signed, sandboxed `.app` carrying a temporary `dropDestination(for: URL.self)` probe
      that logs **booleans and lengths only** through `OSLog` — never a path, never a filename, nothing
      durable (`docs/privacy.md`, SECURITY.md).
- [ ] 2.2 Record, per dropped item: `isFileURL`; whether the path is in file-reference form
      (`/.file/id=`); whether `(url as NSURL).filePathURL` differs from the delivered URL; whether
      `lastPathComponent` matches the file's real name; whether `pathExtension` is present; whether it
      is a directory; the value returned by `startAccessingSecurityScopedResource()`; and whether the
      file is readable **both inside the drop handler and after the asynchronous hop**.
- [ ] 2.3 Cover the matrix: `~/Music`, Desktop, Downloads, an external volume, a downloaded iCloud file,
      an evicted iCloud file, an alias, a symlink, a folder, an `.app` bundle, two files at once, a
      Safari link, and a Mail attachment (file promise).
- [ ] 2.4 Write the findings to `docs/spikes/` and remove the probe. Decide on that evidence whether
      normalisation is required and **who owns it**: the drop adapter in `AudioInspectorApp` if only the
      drop can produce reference URLs, or `AudioFileReferenceMapper` if the panel can too. Update
      ADR-0014's risk section with the observed result.

## 3. Dropped-payload routing in `AudioInspectorApp`

- [ ] 3.1 Add a pure, `Sendable` validator (`Sources/AudioInspectorApp/Import/DroppedSource.swift`)
      turning `[URL]` into one inspectable local file or a typed rejection: exactly one element, a file
      URL, not a directory — plus the normalisation task 2.4 decided on, if any.
- [ ] 3.2 Add the drop inspection action to `AppContainer`, building a `SourceInspectionCoordinator`
      with a constant source provider. **`SourceInspectionCoordinator`, `SourceSelection`,
      `AudioFileReferenceMapper`, the reader and the use case are not modified.**
- [ ] 3.3 Apply `.dropDestination(for: URL.self, action:isTargeted:)` to `RootView`'s outer container so
      the whole window is the target in every state, decline the drop while an inspection is running,
      and hold the targeting flag in `@State`.

## 4. One state machine shared by panel and drop

- [ ] 4.1 Extract `ImportFlowModel.inspect(using:)` and make `selectAndInspect()` delegate to it, so both
      entry points share one implementation of the transitions. The panel's public signature and
      behaviour are unchanged, and the re-entrancy guard and neutral cancellation are shared rather than
      duplicated.
- [ ] 4.2 Confirm the existing `ImportFlowModelTests` still pass **without being modified** — the
      regression criterion for the panel path.

## 5. Rejection channel and visual feedback

- [ ] 5.1 Add `DropRejection` to `FeatureImport`: a small enum with no `URL`, no AppKit and no filesystem
      type, and expose it on `ImportFlowModel` as an optional value **outside** `ImportFlowState`,
      cleared by any accepted selection from either entry point.
- [ ] 5.2 Render the targeting highlight and the rejection notice in `ImportFlowView`: instructive copy
      ("Drop one audio file"), never confirmatory; initial text mentioning both the panel and dragging,
      keeping the read-only promise visible; the `Choose audio file…` button preserved as the primary
      path.
- [ ] 5.3 Accessibility: feedback is real text and never colour alone, the highlight carries an
      accessibility label, and the rejection notice is reachable by VoiceOver.

## 6. Automated boundary rule

- [ ] 6.1 Add a rule to `Scripts/check-boundaries.sh` rejecting `import AppKit` and real use of the `URL`
      type in `Sources/Feature*`: comment lines filtered, `URL` matched as a whole word, `import
      Foundation` still allowed.
- [ ] 6.2 Add a controlled negative check so a broken pattern cannot become a rule that never fires, and
      confirm the current tree passes.

## 7. Tests

No unit test opens a panel or performs a real drag; the three tiers stay separate.

- [ ] 7.1 Unit — payload validation: empty, two or more items (rejected **whole**, first not taken), a
      non-file URL, a directory, a valid file; plus reference-URL normalisation **only if task 2.4 proved
      it necessary**.
- [ ] 7.2 Unit — flow model: re-entrancy holds for `inspect(using:)`; a drop during `.working` starts no
      second inspection; a rejection leaves the state untouched and preserves a previous report; a
      rejection is cleared by the next accepted selection; a valid drop from a report ends in the new
      report.
- [ ] 7.3 Unit — visual state modelled as data (targeting flag, rejection → text), asserted without
      snapshots.
- [ ] 7.4 Integration — a dropped URL injected through the existing coordinator seam inspects the file
      **exactly once** and returns its report.
- [ ] 7.5 Integration — the composition root builds the drop action; the real coordinator driven by a
      dropped URL produces a report; and the source file is byte-identical afterwards (ADR-0013).
- [ ] 7.6 Integration — the same file inspected via panel and via drop yields the same exported JSON
      apart from the per-export envelope fields: the assertion that keeps both entry points on one
      pipeline.

## 8. Security and privacy records

- [ ] 8.1 Correct the single claim in `SECURITY.md` that files are reached only through native panels,
      to explicit user interactions through native panels **or** drag & drop. No ADR is duplicated and
      the policy is not rewritten.
- [ ] 8.2 Apply the same minimal correction in `docs/privacy.md`.

## 9. Manual sandboxed validation

- [ ] 9.1 Extend the manual validation runbook with a drag & drop section covering: a valid drop from
      Finder in each tested location; a drop while a report is displayed; a folder; an `.app` bundle; a
      Safari link; two files at once; a Mail attachment; an evicted iCloud file; an alias; a drop during
      an inspection; export after a dropped inspection; and the displayed name matching the real one.
- [ ] 9.2 Execute it against a signed, sandboxed build and record the results, including the source
      file's hash before and after.

## 10. Gates and closure

- [ ] 10.1 Four gates green: `./Scripts/check-boundaries.sh` (including the new rule),
      `swift build -Xswiftc -warnings-as-errors` (no deprecation diagnostic from the chosen overload),
      `swift test`, and `openspec validate --all --strict`; plus `swiftformat --lint . && swiftlint`.
- [ ] 10.2 Confirm the diff touches no domain, media, analysis, `FeatureAnalysis`, exporter, entitlement
      or `Package.swift` file, and adds no dependency.
- [ ] 10.3 Move ADR-0014 to `Accepted`, update `CURRENT.md`, and archive the change.
