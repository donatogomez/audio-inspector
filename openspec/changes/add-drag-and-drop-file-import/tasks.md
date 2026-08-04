# Implementation Tasks

Design only in this step — **no task below is implemented or checked.** Group 1 is the documentary
commit that opens the change; every other group is implementation work to be done on its own branch.
Each task is small, verifiable, maps to one logical commit, and contains nothing out of scope.

Group 2 deliberately comes before any routing code: its outcome decides whether URL normalisation is
needed at all and, if so, which layer owns it.

## 1. Decision record and OpenSpec contract

- [x] 1.1 Write ADR-0014 (`docs/adr/0014-drag-and-drop-file-access.md`, status `Proposed`): panel and
      drag & drop as two mechanisms of one explicit user selection; entitlement unchanged; temporary
      access; no bookmarks or persistence; the same `SourceInspectionCoordinator`; `URL` and AppKit
      confined to `AudioInspectorApp`; whole-drop rejection for multi-item drops; why a copying
      `Transferable` representation is rejected; instructive-only targeting feedback as an API
      limitation; and its relationship to ADR-0010 and ADR-0013 **without modifying either**.
- [x] 1.2 Add ADR-0014 to the index in `docs/adr/README.md`.
- [x] 1.3 Create the change `add-drag-and-drop-file-import` with `proposal.md`, `design.md`, the
      `MODIFIED` delta on `audio-file-inspection`, and this task list. The promoted spec is not edited
      directly.
- [x] 1.4 `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` green.

## 2. Observe the URL a dropped file actually delivers (manual, sandboxed)

Blocks tasks 3 and 5. `swift test` cannot reach any of this: the package runs unsandboxed and unsigned
(`docs/testing-strategy.md`).

- [x] 2.1 Built a signed, sandboxed `.app` carrying a temporary `dropDestination(for: URL.self)` probe
      surfacing **booleans and counts only** in a copyable diagnostic panel — never a path, never a
      filename, never an extension value, nothing durable (`docs/privacy.md`, SECURITY.md).
- [x] 2.2 Recorded, per dropped item: item count; `isFileURL`; `isFileReferenceURL`; whether
      `(url as NSURL).filePathURL` differs from the delivered URL; whether the name and extension are
      non-empty; whether it is a directory; whether it conforms to `UTType.audio`; the value returned by
      `startAccessingSecurityScopedResource()`; readability **both inside the drop handler and after an
      asynchronous hop**; and whether the URL still resolved to the same resource afterwards.
- [ ] 2.3 Cover the rest of the matrix: a downloaded iCloud file, an evicted iCloud file, an alias, a
      symlink, an `.app` bundle, and a Mail attachment (file promise). **Partially done** — Downloads,
      Music, another authorised location, a folder, two files at once and a web item were observed and
      are recorded in ADR-0014; the entries listed here were not, so a file-reference URL is unproven
      rather than impossible.
- [x] 2.4 Removed the probe and recorded the findings in ADR-0014 (*Evidence from the sandboxed
      observation*) and in `design.md`, rather than in `docs/spikes/`, so the evidence sits next to the
      decision it settles. **Decision: no normalisation** — Finder delivered conventional path URLs with
      `filePathURL` identical, so `filePathURL` is not consulted, no file-reference adapter is written
      and `AudioFileReferenceMapper` is untouched.

## 3. Dropped-payload routing in `AudioInspectorApp`

- [x] 3.1 Add a pure, `Sendable` validator (`Sources/AudioInspectorApp/Import/DroppedSource.swift`)
      turning `[URL]` into one inspectable local file or a typed rejection: exactly one element, a file
      URL, not a directory — plus the normalisation task 2.4 decided on, if any.
- [x] 3.2 Add the drop inspection action to `AppContainer`, building a `SourceInspectionCoordinator`
      with a constant source provider. **`SourceInspectionCoordinator`, `SourceSelection`,
      `AudioFileReferenceMapper`, the reader and the use case are not modified.**
- [x] 3.3 Apply `.dropDestination(for: URL.self, action:isTargeted:)` to `RootView`'s outer container so
      the whole window is the target in every state, decline the drop while an inspection is running,
      and hold the targeting flag in `@State`.

## 4. One state machine shared by panel and drop

- [x] 4.1 Extract `ImportFlowModel.inspect(using:)` and make `selectAndInspect()` delegate to it, so both
      entry points share one implementation of the transitions. The panel's public signature and
      behaviour are unchanged, and the re-entrancy guard and neutral cancellation are shared rather than
      duplicated.
- [x] 4.2 Confirm the existing `ImportFlowModelTests` still pass **without being modified** — the
      regression criterion for the panel path.

## 5. Rejection channel and visual feedback

- [x] 5.1 Add `DropRejection` to `FeatureImport`: a small enum with no `URL`, no AppKit and no filesystem
      type, and expose it on `ImportFlowModel` as an optional value **outside** `ImportFlowState`,
      cleared by any accepted selection from either entry point.
- [x] 5.2 Render the targeting highlight and the rejection notice in `ImportFlowView`: instructive copy
      ("Drop one audio file"), never confirmatory; initial text mentioning both the panel and dragging,
      keeping the read-only promise visible; the `Choose audio file…` button preserved as the primary
      path.
- [x] 5.3 Accessibility: feedback is real text and never colour alone, the highlight carries an
      accessibility label, and the rejection notice is reachable by VoiceOver.

## 6. Automated boundary rule

- [x] 6.1 Add a rule to `Scripts/check-boundaries.sh` rejecting `import AppKit` and real use of the `URL`
      type in `Sources/Feature*`: comment lines filtered, `URL` matched as a whole word, `import
      Foundation` still allowed.
- [x] 6.2 Add a controlled negative check so a broken pattern cannot become a rule that never fires, and
      confirm the current tree passes.

## 7. Tests

No unit test opens a panel or performs a real drag; the three tiers stay separate.

- [x] 7.1 Unit — payload validation: empty, two or more items (rejected **whole**, first not taken), a
      non-file URL, a directory, a valid file; plus reference-URL normalisation **only if task 2.4 proved
      it necessary**.
- [x] 7.2 Unit — flow model: re-entrancy holds for `inspect(using:)`; a drop during `.working` starts no
      second inspection; a rejection leaves the state untouched and preserves a previous report; a
      rejection is cleared by the next accepted selection; a valid drop from a report ends in the new
      report.
- [x] 7.3 Unit — visual state modelled as data (targeting flag, rejection → text), asserted without
      snapshots.
- [x] 7.4 Integration — a dropped URL injected through the existing coordinator seam inspects the file
      **exactly once** and returns its report.
- [x] 7.5 Integration — the composition root builds the drop action; the real coordinator driven by a
      dropped URL produces a report; and the source file is byte-identical afterwards (ADR-0013).
- [x] 7.6 Integration — the same file inspected via panel and via drop yields the same **report**, field
      by field, apart from the per-reference `id` (a fresh `UUID`, playing the role `generatedAt` plays
      in the JSON). This is the assertion that keeps both entry points on one pipeline. The export is
      deliberately **not** re-run: `EndToEndFlowTests` already covers it, and the exporter is a pure
      function of the report, so identical reports export identically.

## 8. Security and privacy records

- [x] 8.1 Correct the single claim in `SECURITY.md` that files are reached only through native panels,
      to explicit user interactions through native panels **or** drag & drop. No ADR is duplicated and
      the policy is not rewritten.
- [x] 8.2 Apply the same minimal correction in `docs/privacy.md`.

## 9. Manual sandboxed validation

- [x] 9.1 Extend the manual validation runbook with a drag & drop section covering: a valid drop from
      Finder in each tested location; a drop while a report is displayed; a folder; an `.app` bundle; a
      Safari link; two files at once; a Mail attachment; an evicted iCloud file; an alias; a drop during
      an inspection; export after a dropped inspection; and the displayed name matching the real one.
- [ ] 9.2 Execute it against a signed, sandboxed build and record the results, including the source
      file's hash before and after.

## 10. Gates and closure

- [x] 10.1 Four gates green: `./Scripts/check-boundaries.sh` (including the new rule),
      `swift build -Xswiftc -warnings-as-errors` (no deprecation diagnostic from the chosen overload),
      `swift test`, and `openspec validate --all --strict`; plus `swiftformat --lint . && swiftlint`.
- [x] 10.2 Confirm the diff touches no domain, media, analysis, `FeatureAnalysis`, exporter, entitlement
      or `Package.swift` file, and adds no dependency.
- [ ] 10.3 Move ADR-0014 to `Accepted`, update `CURRENT.md`, and archive the change.
