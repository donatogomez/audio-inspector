# Implementation Tasks

**Nothing is implemented. Only group 1 is done** — the change's artifacts exist and validate.

**Group 0 is the acceptance matrix, not a spike.** It turns the evidence in
`docs/spikes/2026-08-05-native-pcm-decoding-validation.md` into criteria the **real adapter** must
satisfy. Its tasks are written first because they define what "working" means, but none of them can be
marked done before group 3 exists — they are verified against the production adapter, never against the
spike package, which is not extended by this change.

Boundaries no task may cross: `AVAudioFile` and every Apple media type stay inside
`AudioInspectorMedia`; no Apple type or error crosses the port; feature modules never see a `URL`; no
`@unchecked Sendable`, no `DispatchQueue`, no lock. The original file is never modified. The
`schemaVersion` 1 contract, `InspectionReport` and the property reader are not touched.

## 0. Acceptance matrix — what the real adapter must satisfy

Every criterion is an automated test against the production adapter unless it says otherwise. A case
that cannot be produced is recorded as **not tested** — never inferred from a neighbouring format.

- [x] 0.1 **WAV** — a generated fixture decodes; frames consumed equal the declared length; the envelope
      spans the file.
- [x] 0.2 **AIFF** — same criteria as 0.1.
- [x] 0.3 **ALAC** — same criteria as 0.1.
- [x] 0.4 **FLAC** — same criteria as 0.1.
- [x] 0.5 **AAC / M4A** — same criteria as 0.1. The spike observed modifications past `frameLength` for
      this codec, so this case is also the regression test for criterion 0.11.
- [x] 0.6 **MP3 — the evidence gap this slice must close.** macOS has no MP3 encoder, so the fixture
      comes from FFmpeg (dev/test-only, ADR-0003). Verify decoding **with the production adapter**;
      never assert support from `afconvert`, FFmpeg or documentation. CI installs no FFmpeg, so a gated
      test is **local evidence, explicitly not CI coverage** and must be labelled as such. If it cannot
      be automated at all, document precisely why and perform a reproducible manual validation
      recording FFmpeg version, exact command, parameters, SHA-256 and observed result. **ADR-0015 stays
      `Proposed` until one of these two is actually done.**
      **Closed by option 3** — `MP3WaveformEvidenceTests`, gated on FFmpeg and **run** on 2026-08-05
      with FFmpeg 8.1.2 (`libmp3lame`): the production adapter decoded a 44 101-frame stereo MP3 into
      2048 buckets, identical at five chunk sizes, with the source byte-identical afterwards. **This is
      local evidence and not CI coverage** — CI installs no FFmpeg and the suite skips there. ADR-0015
      stays `Proposed`: 1.4 also requires group 7.
- [x] 0.7 **Corrupt / truncated file** — fails in a way the caller can handle: no crash, no hang,
      bounded resources, and the outcome is a stated absence rather than a fabricated envelope.
- [x] 0.8 **Long file** — completes within a sane time and its envelope spans the file; used to fix the
      chunk size left open in `design.md`.
- [x] 0.9 **Chunked reading** — the same file read at several chunk sizes yields **identical** buckets.
- [x] 0.10 **EOF** — the loop is bounded by `framePosition < length`; a read past the end is never
      relied upon, and the bare error the spike observed is never treated as data.
- [x] 0.11 **Strict `frameLength`** — only the frames a read reports as valid contribute. Asserted twice:
      identical buckets across chunk sizes (0.9), and an unchanged envelope for a file whose final chunk
      is short regardless of what the buffer's tail holds.
- [x] 0.12 **Cancellation** — a cancelled read stops at the next chunk boundary, produces no envelope
      presented as complete, and leaves no file open.
- [x] 0.13 **Bounded memory** — assert what the suite can genuinely observe: the read is chunked and the
      full decoded track is never retained. Do **not** claim to measure resident memory in `swift test`;
      any figure quoted comes from a measured run and is labelled as such.

## 1. OpenSpec contract and the decision record

- [x] 1.1 Open the change with `proposal.md`, `design.md`, the `ADDED` delta on the new
      `waveform-visualization` capability, the `MODIFIED` delta scoping the no-DSP requirement on
      `audio-file-inspection`, and this task list. The promoted specs are not edited by hand.
- [x] 1.2 `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` green.
- [x] 1.3 Write **ADR-0015** in `Proposed`, citing the spike report by section: `AVAudioFile` over
      `AVAssetReader`, the `frameLength` invariant, and the reduction living in Media. It **references
      ADR-0003 and does not edit it**. Add its row to `docs/adr/README.md`.
- [ ] 1.4 Move ADR-0015 out of `Proposed` **only** when group 0 passes with MP3 resolved (0.6) and group
      7's manual validation is done. Not before, and never on partial evidence.

## 2. The domain port and the envelope value type

- [x] 2.1 Add `WaveformGenerating` to `AudioInspectorDomain/Ports/` — a small `Sendable` protocol taking
      `AudioFileReference` and returning the envelope value type, with a typed `throws` in the domain's
      own error space. No `AVAudioFile`, `AVAudioPCMBuffer`, `AVAudioFormat`, `NSError` or `OSStatus`
      appears in its signature.
- [x] 2.2 Add the envelope value type: `Sendable`, `Equatable`, carrying buckets of minimum and maximum.
      It holds no view width, no normalisation factor and no URL. Its documentation states that it is a
      **combined envelope across all channels** and is **not** a mono mix or a downmix.
- [x] 2.3 Implement the bucket arithmetic as pure domain code: `bucketCount = min(2048, frameCount)` and
      the integer frame→bucket mapping, unit-testable with no file and no framework.
- [x] 2.4 Give the waveform its own error space, **disjoint** from `InspectionError` and
      `PropertyFailure`. Represent "no usable frame count" as an **absence outcome**, not an error.

## 3. The Media adapter

- [x] 3.1 Implement the port in `AudioInspectorMedia` with `AVAudioFile`, resolving the `URL` through
      the constructor seam exactly as `AVFoundationAudioFilePropertyReader` does (ADR-0010). A fresh
      adapter per operation; no shared state, no registry.
- [x] 3.2 Read in fixed-size chunks with a reused buffer, folding each chunk into the buckets it spans,
      in a single pass. The decoded track is never held in full, and bucket boundaries never depend on
      chunk boundaries.
- [x] 3.3 **Consume exactly the reported frame count; never the buffer's capacity.** One place in the
      code reads a buffer, and it takes its bound from there. The reason is written beside it: the
      surplus is deterministic, content-derived audio the API declined to report, so including it would
      draw something plausible and wrong.
- [x] 3.4 Confine each `AVAudioFile` to the task that opens it and never share an instance — the
      `NS_SWIFT_SENDABLE` annotation removes the compiler's objection, not the mutable read cursor. No
      `@unchecked Sendable`, no `DispatchQueue`, no lock.
- [x] 3.5 Bound the loop with `framePosition < length` and honour `Task.isCancelled` at chunk
      boundaries.
- [x] 3.6 Catch every Apple error and translate it into the domain's waveform error space, classified by
      **scope** and never by SDK numeric code. No `NSError`, `AVError`, `OSStatus` or Apple user-info
      string escapes the adapter.
- [x] 3.7 Confirm the adapter only reads: nothing writes, renames, moves or truncates the file.
- [x] 3.8 Add the port fake to `AudioInspectorTesting` so use-case and feature tests need no real file.

## 4. Wiring, the access window and the flow state

- [x] 4.1 Produce the waveform inside `SourceInspectionCoordinator.inspect(_:)`, within the existing
      security-scoped window — it closes on return (ADR-0010), so a lazy produce-on-appear is not
      possible. Properties first, samples second; a global inspection failure skips the sample read.
- [x] 4.2 Confirm nothing changes in the sandbox story: no bookmark, no retained URL, no new
      entitlement, nothing persisted.
- [x] 4.3 Carry the waveform **beside** the report through the coordinator's outcome and
      `ImportFlowModel.State.report`, with absence as a first-class value. `InspectionReport`,
      `TechnicalProperties` and `Property` are untouched.
- [x] 4.4 Confirm boundary rule 10 still holds: no feature module gains a `URL` or an AppKit import.

## 5. Presentation

- [x] 5.1 Draw the envelope in `FeatureAnalysis` with SwiftUI from the bucket values — no bitmap, no
      image file, no dependency. The view maps buckets onto the width it has; the domain type stays
      view-independent and resizing never decodes again.
- [x] 5.2 No interaction: no playback, zoom, scrubbing, selection or cursor; pointer and scroll activity
      leave the drawing and its data unchanged.
- [x] 5.3 The label states only what the drawing **is** — an amplitude envelope of the whole file — and
      never characterises the signal as loud, quiet, clipped, compressed, dynamic, healthy or damaged,
      and never presents it as a measurement or as evidence about bit depth, encoding or integrity.
- [x] 5.4 State an absent waveform in words rather than showing an empty area.
- [x] 5.5 Keep colour tied to the state of the reading, never to the audio, consistent with the report
      surface already shipped.

## 6. Tests

- [x] 6.1 Domain unit tests for the bucket arithmetic: the 2048 cap, a file shorter than the cap
      producing no empty bucket, and the integer frame→bucket mapping.
- [x] 6.2 Envelope honesty: two channels in opposing polarity do not cancel; two files at clearly
      different levels yield proportionally different envelopes with no per-file normalisation; sample
      values beyond `[-1, 1]` are preserved rather than clamped.
- [x] 6.3 Adapter integration over the group-0 matrix, one test per row, with the FFmpeg-dependent case
      gated and **not** counted as coverage when it is skipped. All thirteen rows are now covered
      against the production adapter. The MP3 row is gated on FFmpeg; its skip message states that a
      skipped run is not evidence of MP3 support, and the skip path was verified against a negative
      control rather than assumed.
- [x] 6.4 The report is unaffected: a file whose samples cannot be read yields the same properties,
      warnings and status as today, and the exported JSON is identical with and without a waveform.
- [x] 6.5 End-to-end: the existing flow test still walks the same pipeline, with a waveform present in
      one case and absent in the other. **No existing assertion is removed or weakened.**
- [x] 6.6 Presentation tests over the model: the accessible label composition, and that no judging
      vocabulary appears anywhere in the waveform surface.

## 7. Accessibility and manual validation

**Deliberately deferred from `improve-report-presentation` to here, and scoped rather than left
drifting.** That change was archived with its accessibility checks open, on purpose; they are **not**
marked done anywhere and no evidence for them exists. Because this slice adds a new element to the same
surface, the pass is performed **once, at the end, over the whole report including the waveform**.

Nothing below may be marked done without actually performing it.

**The waveform's own checks:**

- [ ] 7.1 Expose the waveform as a single accessibility element with a composed label that says what it
      is and not what it looks like.
- [ ] 7.2 VoiceOver: the waveform is announced as an amplitude envelope of the file, with no
      characterisation of the audio; an absent waveform is announced as unavailable.
- [ ] 7.3 Confirm every meaning the drawing conveys has a textual alternative, and that no meaning
      depends on colour alone.
- [ ] 7.4 Contrast: the drawing and its surrounding text remain distinguishable in light and dark
      appearance, and against the report's background.
- [ ] 7.5 Accessibility text sizes: the waveform's label and its surroundings stay legible and nothing is
      clipped at the system's largest sizes.

**The report's inherited checks, repeated over the finished surface:**

- [ ] 7.6 Confirm by eye that no underscore code, enum name, wire key, raw UTI or bare FourCC appears
      anywhere on the report (inherited `improve-report-presentation` 9.1).
- [ ] 7.7 VoiceOver over the whole report: each property reads as one coherent element, warnings and
      status are announced, and the export action is reachable in a sensible order (inherited 9.2).
- [ ] 7.8 Accessibility text sizes across the whole report: legible, nothing clipped (inherited 7.4 and
      9.3).
- [ ] 7.9 Confirm no colour carries meaning on its own anywhere on the report (inherited 7.4 and 9.4).
- [ ] 7.10 Record the result in `docs/manual-validation-mvp.md` as a durable statement, without per-run
      details, and state plainly which of the inherited checks were performed and which were not.

## 8. Gates and closure

- [ ] 8.1 Four gates green — `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test`,
      `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` — plus the Xcode app build.
- [ ] 8.2 Confirm the diff's scope: no new dependency, entitlements unchanged, the JSON exporter and the
      `schemaVersion` 1 contract byte-identical, `InspectionReport` and the property reader untouched,
      and `AudioInspectorAnalysis` still empty.
- [ ] 8.3 Decide ADR-0015's status from what was actually done (see 1.4), update `CURRENT.md`, and
      archive through `openspec archive` without editing the promoted specs by hand.
