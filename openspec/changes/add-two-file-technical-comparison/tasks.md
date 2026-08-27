# Implementation Tasks

**Only group 1 is done**: this change is the contract, written before any implementation. Nothing else
exists.

Boundaries no task may cross: the comparison is **pure domain** — no port, no adapter, no framework, no
`URL`, no I/O, no `async`, no `throws`. `AVFoundation` stays in `AudioInspectorMedia`, Accelerate in
`AudioInspectorAnalysis`, and features never import either. No `@unchecked Sendable`, no
`DispatchQueue`, no lock. The original files are never modified. **`InspectionReport`,
`TechnicalProperties`, `Property`, `InspectionWarning`, `InspectionStatus`, the property reader, the
spectrogram, the waveform and the `schemaVersion` 1 exporter are not touched.**

## 1. The contract and the decision record

- [x] 1.1 Open the change with `proposal.md`, `design.md`, this task list and the `ADDED` delta on the
      new `audio-file-comparison` capability. `audio-file-inspection` is **not** modified: inspecting a
      single file, and its export, behave exactly as today.
- [x] 1.2 `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` green.
- [x] 1.3 Write **ADR-0017** in `Proposed`, fixing the three-way semantics, the absence of ordering and
      of any aggregate, exact duration, declared-vs-estimated separation, and the deferral of hashes,
      signal comparison and export. It **references ADR-0008 and does not edit it**. Add its row to
      `docs/adr/README.md`.
- [x] 1.4 Answer design.md's open questions before group 2 begins, and record each answer where the
      decision lives. **All four are closed** (design.md §13): `fileExtension` and `sizeBytes` are
      shown but never judged; duration is exact `Double` equality; the comparison surface sits **beside**
      the report rather than replacing it, derived from the flow invariants rather than chosen; and the
      first file's visualisations stay exactly as they are. Closing the fourth surfaced one decision
      that belongs to group 4 — whether the second inspection requests visualisations nobody displays —
      and the contract invariant it cannot break is fixed: **the comparison depends only on the two
      reports.**
- [ ] 1.5 Move ADR-0017 out of `Proposed` **only** when the comparison exists against production code
      and its surface has been validated by a person looking at it. Not before, and never on partial
      evidence.

## 2. The comparison semantics in the domain

- [x] 2.1 Add `PropertyState` — `available`, `unavailable`, `unsupported`, `uncertain`, `failed` — as
      the state of one side of a comparison. It **includes `available`** and therefore cannot be
      `WarningKind`, which deliberately excludes it; state that in the type's own documentation so the
      two are not later unified.
- [x] 2.2 Add `ComparisonGap`, carrying the state of each side. Its initialiser is **failable and
      refuses two `available` states**, so a gap that contradicts itself is unrepresentable — the
      device `WaveformBucket.init?` already uses. This is the only reason it is a type rather than two
      loose parameters, and the documentation should say so.
      **Done as written, then superseded by something stronger — recorded rather than rewritten.** The
      failable initialiser worked, but the rule's own caller had already proved the pair impossible and
      needed a way past the refusal, which was a `fileprivate` unchecked initialiser whose safety rested
      on the order of two switch branches. The gap is now **three cases that each name at least one
      non-available side**, so `(available, available)` has no spelling: 24 constructible gaps, exactly
      the 24 that are gaps, and the twenty-fifth does not exist rather than being refused. The failable
      states-based initialiser survives as a convenience and still refuses the pair; the backdoor is
      gone. Every group 2 test passed untouched across the change.
- [x] 2.3 Add `PropertyComparison<Value>` with exactly three cases — `same(Value)`,
      `different(first:second:)`, `incomparable(ComparisonGap)` — with conditional `Sendable` and
      `Equatable` mirroring `Property`. It carries **no ordering, no delta, no ratio**, does not
      conform to `Comparable`, and exposes **no** accessor returning a preferred side.
- [x] 2.4 Implement the single rule that produces one: compare **only** `available` against
      `available`; every other combination becomes `incomparable` carrying both states. Written once,
      generic over `Value: Equatable`, so no field can drift from the rule.
- [x] 2.5 Confirm no comparison type is `Codable` and none can reach the exporter. They never enter the
      `schemaVersion` 1 contract.

## 3. The aggregate and the pure operation

- [x] 3.1 Add `FileComparison`: the two reports plus one `PropertyComparison` per compared field, as a
      `Sendable`, `Equatable` value object. **No lifecycle, no identity, no aggregate root, no score,
      no winner, no confidence**, and **no exposed count of differences** — a count rendered as a
      measure is an aggregate score in disguise. **No `allSame`, `isIdentical` or `matches` either**:
      that is the same aggregate compressed to one bit, and it is the most tempting of the lot because
      it looks like a convenience. *"Every comparable property agreed"* and *"the two files are the
      same"* are different statements, and a boolean would blur them.
- [x] 3.2 Build it through an **initialiser on `FileComparison`**, not a use case: not `async`, not
      `throws`, not failable. **`CompareInspectionsUseCase` is deliberately not created** — there is no
      port, no I/O and no failure to orchestrate, and building one for symmetry with
      `InspectAudioFileUseCase` is the speculative abstraction this project refused when it declined
      `SpectrogramGenerating`. **Reversal criterion:** introduce one if comparison ever needs to consult
      a port, re-read a file, or fail.
- [x] 3.3 Compare exactly the eight fields of `TechnicalProperties` and no others. `fileExtension`,
      `sizeBytes`, `modifiedAt`, `displayName`, `source` and `id` are not compared (see 1.4 for the
      first two). Note in the type that **there is no `format` property** — `container` and `codec` are
      separate technical facts.
- [x] 3.4 Keep `declaredBitrate` and `estimatedBitrate` comparable **only against their own
      counterpart**. A test must fail if any code path ever compares one against the other.
- [x] 3.5 Carry the two reports **whole** rather than copying their fields, so the surface reads each
      file's own facts, warnings and status from one place and no second copy can drift.

## 4. Choosing and holding a second file

- [x] 4.1 Add the second-file selection from an open report, reusing the **existing** selection path and
      the **existing** inspection pipeline unchanged. No multiple selection, no two-file drop, no
      dedicated two-slot mode, no batch.
- [x] 4.2 **Change what a new selection means, deliberately and in one place.** Today every selection
      supersedes the previous one through a single operation identity; a comparison needs a second
      inspection that does **not** supersede the first. Give the second inspection its **own** operation
      identity, disjoint from the first's, so a stale second result can be dropped without touching the
      first report. This is the one real change to the flow's semantics and the main risk in the slice.
- [x] 4.3 Carry the comparison **beside** the report, in the shape the waveform and spectrogram already
      established — never inside `InspectionReport`.
- [x] 4.4 Hold each file's access for **its own inspection only** (ADR-0010): two sequential windows,
      each released by its own `defer`, nothing retained across them, no bookmark, no location
      disclosed for either file.
      **Satisfied by not changing the thing that guarantees it.** `SourceInspectionCoordinator` is
      untouched: it is a struct owning no state, so the second file runs the identical path — its own
      `startAccessingSecurityScopedResource`, its own `defer`, its own reader, generator and decoder
      built fresh from the factories. Nothing is retained across the two, no bookmark is created, and
      the flow never sees a `URL`.
      **One case is not sequential, and it is recorded rather than hidden.** A comparison may begin
      while the first file's visualisations are still being produced — which invariant 4.5 *requires*,
      since that work must still land. Both scopes are then briefly open at once. That is a consequence
      of 4.5 rather than a choice, and it is safe: each scope is per-file, acquired and balanced by its
      own inspection's `defer`, and neither can outlive its call. Blocking a comparison until the first
      file's analysis finished would trade a real delay for a property nothing needs.
- [x] 4.5 Confirm the first file's waveform and spectrogram operations are **unaffected** by a second
      inspection starting, finishing, failing or being cancelled — they are already independent
      operations with independent cancellation, and this must stay true. A result of the first file's
      work still in flight when the second is chosen must still reach the first file's presentation.
- [x] 4.6 Decide whether the second inspection **requests** a waveform and a spectrogram at all, given
      that this MVP displays neither. Name the cost either way — it is seconds of analysis per
      comparison. The invariant this cannot break: **the comparison depends only on the two reports**,
      so it is built the moment the second report settles and waits for nothing else.
      **Decided: the second file runs the same pipeline, unchanged, and its visualisations are
      discarded.** The evidence, rather than the preference:
      **(a) A report-only mode cannot be expressed honestly today.** `SourceInspectionOutcome.inspected`
      requires a `WaveformOutcome` and a `SpectrogramOutcome`, and neither has a case meaning *not
      asked for*. The nearest, `.unavailable`, means *the file offered nothing* — so a report-only path
      would have to state something false about the second file in order to save time. Adding a case
      would change two outcome types, both matching state types, the presentation, and the tests that
      exist specifically to keep those meanings apart (`WaveformErrorTests` pins three distinct
      outcomes; `SpectrogramCopyTests` pins that absence, failure and too-short are three different
      statements). That is a wide change to shared contracts for a saving nobody can currently see.
      **(b) The cost is real, bounded, and off the critical path.** Group 12 measured a whole
      spectrogram generation at **0.9 s in Release** for a ten-minute 68 MB file, with the waveform's
      own read on top — so roughly one to two seconds of work per comparison on a large file, less on a
      typical track. None of it delays anything: the comparison is built from the second **report**, so
      it is on screen before either visualisation starts.
      **(c) The next slice needs them.** `add-two-file-visual-comparison` will draw exactly these two
      models. Adding a report-only mode now and removing it then is churn in both directions.
      **Reversal criterion:** revisit if a comparison is ever performed over many files, or if the
      visual slice is abandoned — at which point the honest fix is a *requested-parts* concept in the
      outcome, not a silent `.unavailable`.
      **Superseded by `add-two-file-visual-comparison`, and recorded rather than rewritten.** The
      decision above is historical and is left exactly as it was made: at the time it was made it was
      correct, and clause (c) — *"the next slice needs them"* — is precisely what came true. That slice
      shipped, and **the second file's visualisations are no longer discarded**: they are collapsed to a
      settled container beside the measurements this task already kept, paired with the first file's
      own, and drawn on shared axes. The line this task named as the point of loss —
      `ImportFlowModel.settle(…)`, where `analyses.settledMeasurements` was kept and the rest went out
      of scope — now keeps both.
      **The reversal criterion was not met; the opposite happened.** It said *"revisit if… the visual
      slice is abandoned"*, and the slice was implemented instead, at **no additional read**: one
      decoder and one decode call per file, counted through the real decoder with the pair retained. So
      the cost this task priced at *"roughly one to two seconds of work per comparison"* was never spent
      twice — the work was already being done, and what changed is that its result is now used.
      **What is not superseded:** (a) stands unchanged. There is still no case meaning *not asked for*,
      no report-only mode was added, and none is needed — the honest fix this task named was never
      required, because the parts it would have skipped turned out to be the parts the next slice
      wanted. **ADR-0025 §4** records the lifetime this places on them; that record, not this task, is
      where the retention rule lives.

## 5. Presentation

- [x] 5.1 Present both files' technical facts with the comparison outcome for each property **stated in
      words**. Colour is never the sole carrier of any meaning, and there is no colour that means good
      or bad.
- [x] 5.2 Present `incomparable` as a sentence naming what each side was — *"this file's format cannot
      express bit depth"* — never as a blank cell, a dash, or a symbol a reader has to decode.
- [x] 5.3 Show each file's warnings and global status **beside its own facts**, not compared.
- [x] 5.4 No badge, arrow, ordering, highlight or emphasis that reads as a preference; no similarity
      figure and no difference count anywhere on the surface.
- [x] 5.5 Expose each property row to an assistive reader as a single element announcing the property,
      both values and the outcome, with no characterisation of either file.
- [x] 5.6 Say the states the surface can be in — no second file chosen, second file loading, second
      inspection failed, second inspection cancelled — **in words**.
      **Three of the four say themselves; the other two are worth stating exactly.** Loading and failed
      each render a sentence. *No second file chosen* renders **no section at all** rather than an empty
      area — there is nothing to explain when the report is simply a report, and a box saying "no
      comparison" would be noise where the task's concern is an unexplained gap. *Cancelled* is **not a
      state the surface can be in**: the flow models a cancelled selection as restoring what was there
      before, so the surface never sees one and does not invent an error for it.

## 6. The test matrix

**Partly closed already, by group 2 rather than out of order.** The semantics arrived with their tests,
so every case that is a fact about `PropertyState`, `ComparisonGap` and `PropertyComparison` alone is
already covered and marked. What stays open needs something that does not exist yet — `FileComparison`
(group 3) or the flow (group 4) — plus 6.12, which is only half assertable and says so.

- [x] 6.1 `available` vs `available`, equal → `same` carrying the value.
- [x] 6.2 `available` vs `available`, unequal → `different` carrying both values.
- [x] 6.3 `available` vs `unavailable` → `incomparable`, both states preserved.
- [x] 6.4 `unavailable` vs `unavailable` → `incomparable`, **not** `same`. Two absences are not an
      agreement.
- [x] 6.5 `unsupported` on either side → `incomparable`, distinguishable from absent.
- [x] 6.6 `uncertain` on either side → `incomparable`, even when both carry equal values.
- [x] 6.7 `failed` on either side → `incomparable`, distinguishable from both absent and unsupported.
- [x] 6.8 Every combination of the five states on each side is covered, and `(available, available)` is
      the **only** one that does not yield `incomparable`.
- [x] 6.9 `ComparisonGap` refuses `(available, available)` — the contradiction is unrepresentable.
- [x] 6.10 `declaredBitrate` is never compared against `estimatedBitrate`, in either direction.
- [x] 6.11 Duration differing by the smallest representable amount yields `different`, with no
      tolerance anywhere in the path.
- [x] 6.12 **No ordering exists**: assert structurally that the comparison exposes no preferred side and
      no `Comparable` conformance.
      **Both halves closed, as a test and as an audit — never conflated.** The `Comparable` half is
      asserted for real — a conformance is a runtime fact, and a positive control confirmed the check
      answers `false` for a non-conforming type and `true` for a conforming one
      (`ComparisonProhibitionTests`). The *no preferred side* half **cannot be asserted honestly**:
      Swift offers no reflection over a type's methods or computed properties, so the only available
      "test" would look for a hand-written string, which proves nothing and would pass against a member
      spelled differently. It stays an **audit**, recorded in the test file's own documentation rather
      than dressed up as a test — and the condition this task was left open for, "until group 3 shows
      whether there is anything better to do," has now been checked rather than assumed: group 3 through
      5 shipped with no such mechanism appearing, and the audit itself has been performed, by reading the
      complete public surface of every comparison-related type — `PropertyComparison`, `ComparisonGap`,
      `PropertyState`/`NonAvailableState`, `FileComparison`, `ComparisonRowDisplay`, `ComparisonFormatter`
      and `ComparisonView` — end to end. None exposes an accessor, a method or a computed property that
      returns one side in preference to the other; `first`/`second` and `sideText`/`accessibilityLabel`
      are purely positional and descriptive. **The residual is named rather than hidden**: a computed
      property added later — `var preferred: InspectionReport` — would not be caught by this audit, only
      by the next one, exactly as 6.13 already notes for a hypothetical `allSame`. That is the limit of
      what an audit can promise, and it is why this stays an audit and never becomes a test.
- [x] 6.13 **No aggregate exists**: assert that neither the comparison nor its presentation exposes a
      score, a percentage, a count of differences, or a boolean summary of the whole comparison.
      **Both halves are now covered.** `Mirror` reports a struct's stored properties, so
      `FileComparison` is shown to store the two reports and the eight comparisons and nothing else. On
      the presentation side the formatter is shown to produce exactly eight rows with no ninth
      summarising them, and **every sentence it can ever render** — all 25 pairings of the five states
      across both sides, plus the fixed copy — is scanned for ranking, direction and aggregate wording.
      **One residual, stated rather than glossed:** `Mirror` cannot see *computed* members, so a
      `var allSame: Bool` added later would not fail these. That is narrower than 6.12's gap — a stored
      aggregate and aggregate wording are both detectable — but it is not nothing.
- [x] 6.14 A cancelled second inspection leaves the first report identical.
- [x] 6.15 A globally failed second file yields a comparison that is entirely `incomparable`, with the
      first report identical.
- [x] 6.16 A superseded second result never reaches the surface.
- [x] 6.17 The same file chosen twice compares as `same` on every comparable property, and nothing
      further is claimed.
      Covered in both halves: a report compared against itself agrees on all seven comparable
      properties while the estimate still does not compare, and the flow exercises the *choosing* —
      selecting the same file as the second one yields exactly that comparison. Nothing in any row or
      any piece of copy claims the two selections are one file, which is the "nothing further is
      claimed" half.
- [x] 6.18 **The export is unchanged**: the JSON for a file inspected alone is byte-identical to the
      JSON for the same file while a comparison is on screen, and no comparison field appears anywhere
      in it.
- [x] 6.19 The comparison is deterministic — the same two reports always produce the same result.

## 7. Accessibility and manual validation

**Partly closed by two real manual passes (2026-08-08), after being blocked and deferred.** The
implementation is finished against production code and the automated matrix is complete (group 6). Three
attempts to run this group against the real app from an automated session were stopped upstream of the
app by two macOS permissions (Screen Recording, Automation toward `System Events`); that block was
recorded as a deferred decision, following this repository's own precedent
(`add-static-spectrogram-visualization` group 10). **A person then ran the comparison itself, over two
passes, with the prepared fixtures**: same file, two distinct files, a corrupted second file, the
replace/close flow, and — in the second pass — light and dark appearance and a VoiceOver attempt. That
closes 7.2, 7.3 and 7.4 on real observation. 7.1 stays open: the VoiceOver attempt reproduced this
project's own **known, pre-existing accessibility gap** (see below) rather than reaching the comparison
rows at all, so nothing about this task was actually observed either way. See
`docs/manual-validation-mvp.md` for exactly what was seen.

Nothing below may be marked done without actually performing it.

- [ ] 7.1 Each property row is announced as a single element with the property, both values and the
      outcome, and no characterisation of either file.
      **Still open — attempted, not satisfied.** VoiceOver validation was attempted. The **existing,
      already-documented accessibility issue reproduced unchanged**: focus remains trapped on *Export
      JSON*, exactly as recorded for the report surface in `docs/manual-validation-mvp.md` (the waveform
      slice's known VoiceOver traversal gap, which never let VoiceOver enter the report's own content,
      let alone a comparison beneath it). There is **no evidence this feature introduces a new
      regression** — the trap sits upstream of the report content, so a comparison on screen could not
      possibly change it — but there is equally no evidence *for* this task: VoiceOver never reached a
      comparison row, so whether it announces as one element or four was not observed by anyone, in any
      session. This project's own precedent (ADR-0015, kept `Proposed` by this identical gap) is that a
      known, reproduced accessibility gap still leaves the task it blocks open rather than closing it by
      exception. No further investigation is planned; the debt is the same pre-existing one, not a new
      one, and is tracked where it already lives.
- [x] 7.2 Every meaning has a textual alternative; nothing depends on colour, position or a symbol.
      **Closed by real observation.** A person read `Same`, `Different`, `Not comparable` and a failed
      second file's own status as words, across three real scenarios against the real app — no meaning
      was inferred from colour or a symbol in any of them. Paired with the existing exhaustive scan over
      every reachable state (`ComparisonPresentationTests`) and the source-level absence of any icon or
      symbol in `ComparisonView`.
- [x] 7.3 The surface remains legible in light and dark appearance.
      **Closed by real observation (second pass, 2026-08-08).** A person viewed the comparison itself —
      not only the spectrogram — in both light and dark appearance and reported it legible in both, with
      correct behaviour across a continuous resize as well.
- [x] 7.4 Read the whole surface by eye and confirm nothing names a preferred file, a verdict, a score,
      an encoder or a bitrate the app did not read.
      **Closed by real observation.** The whole surface was read by eye across the same file, two
      distinct files, and a corrupted second file, plus the replace/close flow; none of `better`, `worse`,
      `winner`, `loser`, `original`, `copy`, `source`, `derived`, `fake`, `transcode` or similar appeared,
      and the subtitle's denial that the comparison ranks the files or claims the same recording was
      confirmed still present.
- [x] 7.5 Record the result in `docs/manual-validation-mvp.md`, stating plainly which checks were
      performed and which were not.
      **Recorded three times: the block, the first real pass, and the second.** Two macOS permissions
      (Screen Recording, Automation) blocked every automated attempt outright; a person's first pass
      closed 7.2 and 7.4; a second pass closed 7.3 and attempted 7.1, reproducing this project's known
      VoiceOver traversal gap rather than observing anything new. Only 7.1 stays open. See the runbook
      section above for the full account of all three.

## 8. Gates and closure

- [x] 8.1 Four gates green — `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test`,
      `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` — plus the Xcode app build.
      All five ran clean: boundaries respected; the build is warning-free; **757 tests in 89 suites**
      passed; OpenSpec strict validated 5/5; and `xcodebuild` on the real `AudioInspector` scheme against
      `App/AudioInspector.xcodeproj` succeeded.
- [x] 8.2 Confirm the diff's scope: no new dependency, entitlements unchanged, the JSON exporter and the
      `schemaVersion` 1 contract byte-identical, `InspectionReport`, `TechnicalProperties`, `Property`,
      the property reader, the spectrogram and the waveform untouched.
      Checked against `main..HEAD`: `Package.swift` is untouched (no new dependency); no `.entitlements`
      file changed; `ReportJSONDTO.swift` is untouched, so the exporter and the v1 contract are
      byte-identical; `InspectionReport.swift`, `TechnicalProperties.swift` and `Property.swift` are
      untouched; no file matching the property reader, the spectrogram or the waveform appears in the
      diff at all. `ReportView.swift`'s own five-line change only adds an optional `comparison`
      parameter defaulting to `.none`, rendered as `ComparisonSection` — additive and inert when unused.
- [x] 8.3 Confirm the domain gained **no port and no framework import**, and that the comparison is
      reachable with no I/O at all.
      `PropertyComparison.swift` and `FileComparison.swift` carry no `import` at all — not even
      `Foundation`. No `protocol` was added to the domain by this branch. Neither type's initialiser is
      `async` or `throws`, so the comparison cannot await, fail or perform I/O — it is a pure function of
      two already-held reports.
- [ ] 8.4 Decide ADR-0017's status from what was actually done (see 1.5), update `CURRENT.md`, and
      archive through `openspec archive` after merge, without editing the promoted specs by hand.
      **Decided, and it stays open.** 1.5 permits promotion only when the surface "has been validated by
      a person looking at it. Not before, and never on partial evidence." Two real passes now close 7.2,
      7.3 and 7.4; **7.1 is the one task still blocking this**, and it stays open on this project's own
      precedent rather than by a fresh judgement call: the identical known VoiceOver traversal gap that
      keeps ADR-0015 `Proposed` was reproduced here too, and that precedent treats a reproduced,
      pre-existing gap as leaving the task it blocks open, not as an exception that closes it. One open
      task out of four is still partial evidence by the ADR's own words, so ADR-0017 stays `Proposed` and
      this task is not done. Archiving is not reached — this repository does not archive a change with an
      open, load-bearing task ahead of it (see `add-static-spectrogram-visualization`, still active on the
      same ground).

## 9. Deferred, and named so it is not quietly dropped

- [ ] 9.1 **Visual comparison** — `add-two-file-visual-comparison`: waveforms and spectrograms side by
      side, on the same absolute scale, with compatible axes. Both models already exist and are already
      built for comparison. Not started here.
- [ ] 9.2 **Comparison export** — a separate document kind with its own version, composing two
      v1-shaped payloads. `schemaVersion` 1 never gains a second inspected file. Not designed here.
- [ ] 9.3 **Evidence comparison** — alignment, gain matching, residual, correlation, spectral
      difference — waits for the metrics it would compare to exist. Not started here.
