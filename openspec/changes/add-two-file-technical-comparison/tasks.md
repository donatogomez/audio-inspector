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
- [ ] 1.4 Answer design.md's open questions before group 2 begins — whether `fileExtension` and
      `sizeBytes` are compared or only shown, and whether exact `Double` equality is the intended
      reading of "exact" for duration. Record each answer where the decision lives, not here.
- [ ] 1.5 Move ADR-0017 out of `Proposed` **only** when the comparison exists against production code
      and its surface has been validated by a person looking at it. Not before, and never on partial
      evidence.

## 2. The comparison semantics in the domain

- [ ] 2.1 Add `PropertyState` — `available`, `unavailable`, `unsupported`, `uncertain`, `failed` — as
      the state of one side of a comparison. It **includes `available`** and therefore cannot be
      `WarningKind`, which deliberately excludes it; state that in the type's own documentation so the
      two are not later unified.
- [ ] 2.2 Add `ComparisonGap`, carrying the state of each side. Its initialiser is **failable and
      refuses two `available` states**, so a gap that contradicts itself is unrepresentable — the
      device `WaveformBucket.init?` already uses. This is the only reason it is a type rather than two
      loose parameters, and the documentation should say so.
- [ ] 2.3 Add `PropertyComparison<Value>` with exactly three cases — `same(Value)`,
      `different(first:second:)`, `incomparable(ComparisonGap)` — with conditional `Sendable` and
      `Equatable` mirroring `Property`. It carries **no ordering, no delta, no ratio**, does not
      conform to `Comparable`, and exposes **no** accessor returning a preferred side.
- [ ] 2.4 Implement the single rule that produces one: compare **only** `available` against
      `available`; every other combination becomes `incomparable` carrying both states. Written once,
      generic over `Value: Equatable`, so no field can drift from the rule.
- [ ] 2.5 Confirm no comparison type is `Codable` and none can reach the exporter. They never enter the
      `schemaVersion` 1 contract.

## 3. The aggregate and the pure operation

- [ ] 3.1 Add `FileComparison`: the two reports plus one `PropertyComparison` per compared field, as a
      `Sendable`, `Equatable` value object. **No lifecycle, no identity, no aggregate root, no score,
      no winner, no confidence**, and **no exposed count of differences** — a count rendered as a
      measure is an aggregate score in disguise.
- [ ] 3.2 Build it through an **initialiser on `FileComparison`**, not a use case: not `async`, not
      `throws`, not failable. **`CompareInspectionsUseCase` is deliberately not created** — there is no
      port, no I/O and no failure to orchestrate, and building one for symmetry with
      `InspectAudioFileUseCase` is the speculative abstraction this project refused when it declined
      `SpectrogramGenerating`. **Reversal criterion:** introduce one if comparison ever needs to consult
      a port, re-read a file, or fail.
- [ ] 3.3 Compare exactly the eight fields of `TechnicalProperties` and no others. `fileExtension`,
      `sizeBytes`, `modifiedAt`, `displayName`, `source` and `id` are not compared (see 1.4 for the
      first two). Note in the type that **there is no `format` property** — `container` and `codec` are
      separate technical facts.
- [ ] 3.4 Keep `declaredBitrate` and `estimatedBitrate` comparable **only against their own
      counterpart**. A test must fail if any code path ever compares one against the other.
- [ ] 3.5 Carry the two reports **whole** rather than copying their fields, so the surface reads each
      file's own facts, warnings and status from one place and no second copy can drift.

## 4. Choosing and holding a second file

- [ ] 4.1 Add the second-file selection from an open report, reusing the **existing** selection path and
      the **existing** inspection pipeline unchanged. No multiple selection, no two-file drop, no
      dedicated two-slot mode, no batch.
- [ ] 4.2 **Change what a new selection means, deliberately and in one place.** Today every selection
      supersedes the previous one through a single operation identity; a comparison needs a second
      inspection that does **not** supersede the first. Give the second inspection its **own** operation
      identity, disjoint from the first's, so a stale second result can be dropped without touching the
      first report. This is the one real change to the flow's semantics and the main risk in the slice.
- [ ] 4.3 Carry the comparison **beside** the report, in the shape the waveform and spectrogram already
      established — never inside `InspectionReport`.
- [ ] 4.4 Hold each file's access for **its own inspection only** (ADR-0010): two sequential windows,
      each released by its own `defer`, nothing retained across them, no bookmark, no location
      disclosed for either file.
- [ ] 4.5 Confirm the first file's waveform and spectrogram operations are **unaffected** by a second
      inspection starting, finishing, failing or being cancelled — they are already independent
      operations with independent cancellation, and this must stay true.

## 5. Presentation

- [ ] 5.1 Present both files' technical facts with the comparison outcome for each property **stated in
      words**. Colour is never the sole carrier of any meaning, and there is no colour that means good
      or bad.
- [ ] 5.2 Present `incomparable` as a sentence naming what each side was — *"this file's format cannot
      express bit depth"* — never as a blank cell, a dash, or a symbol a reader has to decode.
- [ ] 5.3 Show each file's warnings and global status **beside its own facts**, not compared.
- [ ] 5.4 No badge, arrow, ordering, highlight or emphasis that reads as a preference; no similarity
      figure and no difference count anywhere on the surface.
- [ ] 5.5 Expose each property row to an assistive reader as a single element announcing the property,
      both values and the outcome, with no characterisation of either file.
- [ ] 5.6 Say the states the surface can be in — no second file chosen, second file loading, second
      inspection failed, second inspection cancelled — **in words**.

## 6. The test matrix

- [ ] 6.1 `available` vs `available`, equal → `same` carrying the value.
- [ ] 6.2 `available` vs `available`, unequal → `different` carrying both values.
- [ ] 6.3 `available` vs `unavailable` → `incomparable`, both states preserved.
- [ ] 6.4 `unavailable` vs `unavailable` → `incomparable`, **not** `same`. Two absences are not an
      agreement.
- [ ] 6.5 `unsupported` on either side → `incomparable`, distinguishable from absent.
- [ ] 6.6 `uncertain` on either side → `incomparable`, even when both carry equal values.
- [ ] 6.7 `failed` on either side → `incomparable`, distinguishable from both absent and unsupported.
- [ ] 6.8 Every combination of the five states on each side is covered, and `(available, available)` is
      the **only** one that does not yield `incomparable`.
- [ ] 6.9 `ComparisonGap` refuses `(available, available)` — the contradiction is unrepresentable.
- [ ] 6.10 `declaredBitrate` is never compared against `estimatedBitrate`, in either direction.
- [ ] 6.11 Duration differing by the smallest representable amount yields `different`, with no
      tolerance anywhere in the path.
- [ ] 6.12 **No ordering exists**: assert structurally that the comparison exposes no preferred side and
      no `Comparable` conformance.
- [ ] 6.13 **No aggregate exists**: assert that neither the comparison nor its presentation exposes a
      score, a percentage, or a count of differences.
- [ ] 6.14 A cancelled second inspection leaves the first report identical.
- [ ] 6.15 A globally failed second file yields a comparison that is entirely `incomparable`, with the
      first report identical.
- [ ] 6.16 A superseded second result never reaches the surface.
- [ ] 6.17 The same file chosen twice compares as `same` on every comparable property, and nothing
      further is claimed.
- [ ] 6.18 **The export is unchanged**: the JSON for a file inspected alone is byte-identical to the
      JSON for the same file while a comparison is on screen, and no comparison field appears anywhere
      in it.
- [ ] 6.19 The comparison is deterministic — the same two reports always produce the same result.

## 7. Accessibility and manual validation

Nothing below may be marked done without actually performing it.

- [ ] 7.1 Each property row is announced as a single element with the property, both values and the
      outcome, and no characterisation of either file.
- [ ] 7.2 Every meaning has a textual alternative; nothing depends on colour, position or a symbol.
- [ ] 7.3 The surface remains legible in light and dark appearance.
- [ ] 7.4 Read the whole surface by eye and confirm nothing names a preferred file, a verdict, a score,
      an encoder or a bitrate the app did not read.
- [ ] 7.5 Record the result in `docs/manual-validation-mvp.md`, stating plainly which checks were
      performed and which were not.

## 8. Gates and closure

- [ ] 8.1 Four gates green — `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test`,
      `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` — plus the Xcode app build.
- [ ] 8.2 Confirm the diff's scope: no new dependency, entitlements unchanged, the JSON exporter and the
      `schemaVersion` 1 contract byte-identical, `InspectionReport`, `TechnicalProperties`, `Property`,
      the property reader, the spectrogram and the waveform untouched.
- [ ] 8.3 Confirm the domain gained **no port and no framework import**, and that the comparison is
      reachable with no I/O at all.
- [ ] 8.4 Decide ADR-0017's status from what was actually done (see 1.5), update `CURRENT.md`, and
      archive through `openspec archive` after merge, without editing the promoted specs by hand.

## 9. Deferred, and named so it is not quietly dropped

- [ ] 9.1 **Visual comparison** — `add-two-file-visual-comparison`: waveforms and spectrograms side by
      side, on the same absolute scale, with compatible axes. Both models already exist and are already
      built for comparison. Not started here.
- [ ] 9.2 **Comparison export** — a separate document kind with its own version, composing two
      v1-shaped payloads. `schemaVersion` 1 never gains a second inspected file. Not designed here.
- [ ] 9.3 **Evidence comparison** — alignment, gain matching, residual, correlation, spectral
      difference — waits for the metrics it would compare to exist. Not started here.
