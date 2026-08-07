# Implementation Tasks

**Only group 0 is done**: the spike ran before this contract existed, and three of its findings changed
the design before it was written. Nothing else is implemented.

Boundaries no task may cross: `AVAudioFile` and every Apple media type stay inside
`AudioInspectorMedia`; **Accelerate stays inside `AudioInspectorAnalysis`**; no Apple or Accelerate type
crosses a port; feature modules never see a `URL`; no `@unchecked Sendable`, no `DispatchQueue`, no
lock. The original file is never modified. The `schemaVersion` 1 contract, `InspectionReport`, the
property reader and the JSON exporter are not touched.

## 0. Spike — measured before the contract

- [x] 0.1 Validate the API: `vDSP.DFT` deprecated, `vDSP.DiscreteFourierTransform` current, neither it
      nor `vDSP.FFT` `Sendable`, and the setup confinable inside one `nonisolated async` function with
      no `@unchecked Sendable`.
- [x] 0.2 Elementary maths: silence at the floor, DC preserved, amplitudes 1.0/0.5/0.1 read with
      **0.000 dB** error, scalloping loss **1.42 dB**, impulse flat across 512/512 bands, a sample at
      1.5 not clamped, two files 20 dB apart still 20 dB apart.
- [x] 0.3 Cutoff discrimination at 16/18/19/20/22 kHz across 44.1, 48, 96 and 192 kHz. All separable;
      narrowest margin 5 reduced bands at 192 kHz. **1024 × 512 is sufficient.**
- [x] 0.4 Reduction: **maximum**, because the mean buried a 20 ms transient by **8.74 dB**. Risk of the
      maximum measured and bounded — an isolated click lights 3 of 1024 columns, the same as the mean.
- [x] 0.5 Channels: negative control recorded. Combining samples in the **time** domain invented **247
      spurious bands**; combining magnitudes in the **frequency** domain invented none and read both
      tones exactly. Costs 1.6–1.7× for stereo.
- [x] 0.6 Edges: chunk-size independence down to one frame, determinism, cancellation yielding no
      partial model, degenerate configurations refused, and zero-padding measured to understate level by
      **6.45 dB** — hence discarded.
- [x] 0.7 Cost and memory: **0.0018 ms** per transform with the setup reused, **10×** slower when
      recreated, 5 min mono in **631 ms**, model **2.00 MiB** independent of duration, one hour
      extrapolated and labelled as such.
- [x] 0.8 Real files: WAV and FLAC of the same audio **identical**; an MP3 and the WAV decoded from it
      report the same edge at **16 774 Hz** against the source's 22 028 Hz. FFmpeg-gated, and the skip
      is not evidence.
- [x] 0.9 Record it in `docs/spikes/2026-08-06-static-spectrogram-validation.md`, reproducible from the
      versioned package, with the falsification criteria written before the measurements.

## 1. OpenSpec contract and the decision record

- [x] 1.1 Open the change with `proposal.md`, `design.md`, the `ADDED` delta on the new
      `spectrogram-visualization` capability, the `MODIFIED` delta on `waveform-visualization` scoped to
      the shared seam, and this task list. `audio-file-inspection` is **not** modified — its promoted
      spec already permits reading samples for another purpose.
- [x] 1.2 `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` green.
- [x] 1.3 Write **ADR-0016** in `Proposed`, citing the spike by section. It **references ADR-0015 and
      does not edit it**. Add its row to `docs/adr/README.md`.
- [ ] 1.4 Move ADR-0016 out of `Proposed` **only** when the format matrix passes against the production
      code and group 10's manual validation is done. Not before, and never on partial evidence.

## 2. The decoding seam and the domain models

- [x] 2.1 Add `AudioDecoding` to `AudioInspectorDomain/Ports/` — a `Sendable` protocol taking
      `AudioFileReference` and yielding PCM in bounded, cancellable chunks with per-channel samples. No
      `AVAudioFile`, `AVAudioPCMBuffer`, `AVAudioFormat`, `NSError` or `OSStatus` in its signature.
      **Decide its exact shape here** — closure fold, `AsyncSequence`, or scoped accessor — from how
      cancellation and the security-scoped window compose (design.md, open question 1).
      **Shape decided: a synchronous, non-escaping callback inside one `async` call.** An
      `AsyncSequence` was rejected on the security-scoped window, not on taste — it would let a consumer
      iterate after `SourceInspectionCoordinator`'s `defer` has closed access, a fault visible only
      under the sandbox and only sometimes. The chosen shape finishes the read before the call returns.
- [x] 2.2 Add the spectrogram value type: `Sendable`, `Equatable`, carrying columns × bands of dBFS
      plus what the axes need. It holds no view size, no normalisation factor and no URL, and is **not**
      `Codable` — it never enters the `schemaVersion` 1 export.
- [x] 2.3 Implement the column and band arithmetic as pure domain code, unit-testable with no file and
      no framework: at most 1024 × 512, the frame→column mapping a function of the file alone.
- [x] 2.4 Give the **shared PCM decoding** its own error space, **disjoint** from `InspectionError`,
      `PropertyFailure` and `WaveformError`. It belongs to `AudioDecoding` and is shared by every
      consumer of the seam, because what fails is the read and a fault there says nothing about the
      visualisation that asked for it. Represent an unusable frame count as an **absence**, not an
      error, and cancellation as its own outcome.
      **Only faults something already requires are named.** Two are produced here by `PCMChunk`, two are
      required by a contract this group states — the description a caller turns into an error, and the
      cancellation the port promises never to report as an absence. Nothing speculative: the adapter's
      codes arrive with the adapter in group 3, as the waveform's did.
- [x] 2.5 **Reject non-finite samples at the boundary**, as `WaveformBucket` does. The spike measured a
      single NaN silently collapsing 184 cells to the floor; the clamp must not be what hides them.
      `PCMChunk` cannot represent one: the refusal carries a stable code rather than a bare `nil`,
      because a ragged chunk, a negative frame and a `NaN` are different faults and only the code says
      which.
- [x] 2.6 Decide whether a zero-frame file yields an empty model or no model, mirroring how
      `WaveformEnvelope` settled it (design.md, open question 3).
      **Decided: a valid model with zero columns.** A file with a readable header and no audio is a
      complete answer, and `nil` stays reserved for "the frame count could not be established" — two
      genuinely different things to tell a user. The spike's `max(1, …)` produced one invented column at
      the floor; `SpectrogramGridMapping` cannot.
- [x] 2.7 Decide whether a separate `SpectrogramGenerating` port is warranted or whether `AudioDecoding`
      plus a pure Analysis function is the whole seam (design.md, open question 2). Introducing a port
      with one consumer "because the architecture map names it" is the speculative abstraction this
      project refuses.
      **Decided: not created.** It would have exactly one implementer and one consumer, and composing
      decode → fold → finish is orchestration, which is the composition root's job — `AudioInspectorApp`
      already depends on `AudioInspectorAnalysis`.
      **Reversal criterion, to be applied in group 5:** introduce it if the real composition turns out
      to hold non-trivial logic that does not belong in the composition root — anything beyond "ask for
      chunks, hand them to the fold, take the result". The known cost of not having it is that flow
      tests cannot script a spectrogram in one line the way `FakeWaveformGenerating` does; the injected
      opaque action that `SourceInspectionAction` already establishes covers that without a domain port.

## 3. The Media adapter for PCM chunks

- [x] 3.1 Implement `AudioDecoding` in `AudioInspectorMedia` with `AVAudioFile`, resolving the `URL`
      through the constructor seam exactly as the existing adapters do (ADR-0010). A fresh adapter per
      operation; no shared state, no registry.
      `AVFoundationAudioDecoder` is a `Sendable` struct holding only the resolver — the file, the buffer
      and every pointer are created inside `decode` and die with it, so there is nothing to share and
      nothing to register.
- [x] 3.2 **Consume exactly the reported frame count; never the buffer's capacity.** The reason is
      written beside it, as it is in the waveform adapter.
      **The obvious way to write this is wrong, and it was measured.** Clamping with
      `min(frameLength, remaining)` makes the invariant unobservable: a short read only ever happens on
      the *final* read (zero short non-final reads across WAV, AAC and FLAC at seven capacities), so on
      every other read the two bounds are equal and on the last the clamp hides the difference —
      substituting `frameCapacity` left all 465 tests green. The loop now consumes exactly what the read
      reported and refuses anything beyond the declared length, which makes the wrong bound fail 14
      tests across all five formats.
- [x] 3.3 Verify the processing format before reading a sample — native deinterleaved float — and fail
      in a controlled way if it does not qualify, never constructing a contiguous pointer over
      interleaved data.
      Channel count, `commonFormat`, `isInterleaved`, `isStandard` and the buffer's own `stride`, all
      before the first read. This is the one fault the domain boundary cannot catch: interleaved samples
      copied as a contiguous run satisfy **every** invariant `PCMChunk` has while describing the wrong
      frames.
- [x] 3.4 Bound the loop with `framePosition < length` and honour `Task.isCancelled` at chunk
      boundaries. Confine each `AVAudioFile` to the task that opens it.
      Cancellation is observed at every boundary and arrives as `cancelled`, never as an absence or as
      a fault of the file. Proved twice: cancelled before starting, and cancelled strictly after the
      body has signalled that it began — plus a third gate showing one cancelled decode leaves another
      running to completion (ADR-0016 decision 15).
- [x] 3.5 Catch every Apple error and translate it into the domain's error space, classified by
      **scope** and never by SDK numeric code.
      Five codes arrived with the branches that throw them: `invalidConfiguration`, `fileAccessDenied`,
      `fileOpenFailed`, `unsupportedProcessingFormat` and `readFailed`; `invalidStreamDescription`
      finally has a producer. Still no `frameRangeOutOfBounds` and no `incompleteCoverage` — a reader
      that overruns or falls short of its declared length is `readFailed`, which is what happened.
- [x] 3.6 Confirm the adapter only reads: nothing writes, renames, moves or truncates the file.
      Asserted over a real decode: the file is byte-identical by SHA-256, its modification date is
      unchanged, and the directory holds exactly the same entries afterwards.
- [x] 3.7 Add the port fake to `AudioInspectorTesting` so Analysis and feature tests need no real file.
      `FakeAudioDecoding` is a `Sendable` struct, not an actor like its two siblings: an actor-isolated
      `decode` could not accept the port's non-`Sendable`, non-escaping callback. Its spy is a separate
      actor, awaited before the callback is entered, so the delivery stays synchronous and the fake's
      timing matches the adapter's rather than merely its signature.

## 4. STFT and reduction in Analysis

- [x] 4.1 Implement the STFT in `AudioInspectorAnalysis` with `vDSP.DiscreteFourierTransform`
      (`.complexReal`), FFT 2048, hop 512, Hann denormalised. **One setup per operation, reused for
      every frame of every channel** — recreating it per frame costs 10×.
      `SpectrogramAccumulator` holds the setup as a `let` initialised once; the source contains exactly
      one `DiscreteFourierTransform(` call, so reuse is structural rather than a promise.
      **One deviation from the spike, measured before taking it.** The spike used `fftSize / 2` bins and
      took the magnitude of element 0, but vDSP packs **DC into `real[0]` and Nyquist into
      `imaginary[0]`** — so that element sums the two ends of the spectrum. Measured: DC at 0.5 with
      Nyquist at 0.5 read **+3.01 dBFS in the lowest bin**, and Nyquist alone lit the *lowest* bin at
      −0.00 dBFS. For an instrument whose subject is where high-frequency energy stops, energy at
      Nyquist appearing in the bass is the wrong failure. Both are unpacked into their own bins
      (`binCount = fftSize / 2 + 1`) and halved onto the common scale; the spike's three exact tone
      readings are unchanged, and the axis now reaches Nyquist literally, as design.md §5 requires.
- [x] 4.2 Scale magnitude by `1 / windowSum` to absolute dBFS, reference 1.0, 20·log10, floor −120.
      **No normalisation of any kind.**
      Pinned by tones on a bin at three amplitudes reading 0.00, −6.02 and −20.00 dBFS — `2 / windowSum`
      reads every one 6 dB high. Silence sits at the floor; two signals 20 dB apart stay 20 dB apart;
      1.5 reads +3.52 dBFS unclamped, exactly as the spike measured.
- [x] 4.3 Transform each channel **separately** and combine by **maximum per bin, in the frequency
      domain**. Never combine samples before transforming. The result is a **combined** spectrogram: not
      a mono mix, not a downmix, and not named as one in code, tests or UI.
      Four properties asserted over real models: two channels carrying different tones both read −6.02
      with no third band lit, opposite polarity does not cancel, a tone in one channel alone survives,
      and left-only equals right-only.
- [x] 4.4 Process channels **sequentially**, sharing the one setup. No per-channel parallelism.
      A plain `for channel in 0 ..< channelCount` loop. The accumulator's source contains no `Task`, no
      task group, no `async` and no `await`.
- [x] 4.5 Reduce by **maximum** in both axes, never by mean.
      A 20 ms transient inside four seconds of silence survives above −9 dBFS; the mean buried the same
      case by 8.74 dB in the spike. In the frequency axis, a lone loud bin still reads −6.02 rather than
      being halved by the quiet bin folded into its band.
- [x] 4.6 **Discard the final incomplete window**; never zero-pad. Write the reason beside it.
      Ten complete windows plus 511 further frames still yield ten columns, and a file shorter than one
      window yields none — with the file's real length still reported.
      **This exposed a defect in the group 2 contract, corrected here.** `Spectrogram` required
      `(frameCount == 0) == (columnCount == 0)`, which assumed frames imply columns. Discarding the
      incomplete window breaks that: a file of 1–2047 frames (up to 46 ms) has audio and no complete
      window, and was **not representable at all**. The invariant is now `columnCount == 0 ||
      frameCount > 0` — columns still require frames, nothing is invented, and neither of the two
      escapes the spike used (an invented column, a padded window) was taken.
- [x] 4.7 Confine the transform setup: created and consumed inside one `nonisolated async` operation, no
      `@unchecked Sendable`, no stored property of a `Sendable` type, no global cache.
      Enforced by the compiler rather than by convention: requiring `Sendable` of the accumulator fails
      with *"does not conform to the 'Sendable' protocol"*, and storing it in a `Sendable` struct fails
      with *"stored property has non-Sendable type"*. No `@unchecked Sendable`, no `static var`, no
      cache and no `DispatchQueue` anywhere in the module.
- [x] 4.8 Confirm no Accelerate type appears in any signature Analysis exposes; `DSPSplitComplex`,
      `vDSP.*` and the setup stay inside.
      Demonstrated by compilation: the test suites import `AudioInspectorAnalysis` **without**
      `@testable` and without importing Accelerate, yet build the accumulator, feed it and read the
      model. An Accelerate type in any exposed signature would stop them compiling.

## 5. Generation and orchestration

- [x] 5.1 Produce the spectrogram inside the existing security-scoped window, as its **own operation**
      with its **own cancellation**, independent of the waveform's.
      `SpectrogramGeneration` composes decode → accumulate → finish; `SourceInspectionCoordinator` runs
      it inside the window it already holds, awaited before the `defer` that releases it. A fresh
      decoder and a fresh accumulator per operation, sharing nothing with the waveform. Proved with the
      **real** decoder over a real file, and by the outcome settling before `inspect` returns.
      **This required a correction to the group 3 contract.** The accumulator needs the stream's shape
      *before* the first chunk — `frameCount` sizes the grid — and the port only returned the
      description after the decode had finished. Every alternative was worse: buffering the file
      destroys bounded memory, decoding twice is the double read the adapter avoids, and deciding the
      grid at the end would hold ~1.2 GB for an hour of audio. The description now travels **with each
      chunk**, which also makes it impossible to receive audio without knowing what stream it came from.
- [x] 5.2 Confirm nothing changes in the sandbox story: no bookmark, no retained URL, no new
      entitlement, nothing persisted.
      The generation opens nothing: no `URL`, no scope, no bookmark. It receives a decoder the
      composition root built, and the composition root is still the only place a `URL` exists. No
      entitlement, plist or persisted value is touched, and a real generation leaves the source
      byte-identical with no file created beside it.
- [x] 5.3 Order the work so the report is delivered first, then the visualisations; a global inspection
      failure skips the sample reads entirely.
      `onReport` still fires the moment the report exists, before either visualisation. A global failure
      now skips **both** sample reads — previously only the waveform's was guarded — asserted with two
      scripted spies recording zero calls each. A preparation failure starts neither.
- [x] 5.4 Confirm cancelling one visualisation does not cancel the other.
      Asserted in both directions and for both failure modes: a cancelled or failed spectrogram leaves
      the waveform's envelope and the report intact, and a cancelled or failed waveform still yields a
      spectrogram. Neither degrades the inspection status, and no warning about a visualisation reaches
      the report (ADR-0016 decision 14).
      **Two separate PCM reads exist for now**, which is the declared cost of not coupling them; moving
      the waveform onto the shared seam is group 9's conditional work, not this group's.

## 6. Wiring and progressive state

- [x] 6.1 Carry the spectrogram **beside** the report, with absence, failure and cancellation as
      first-class values. `InspectionReport`, `TechnicalProperties` and `Property` are untouched.
      `SpectrogramOutcome` moves into `FeatureImport` beside `WaveformOutcome`, and `SpectrogramState`
      adds the one case an outcome does not have — `loading`. **Cancellation settles into nothing**:
      `SpectrogramState(.cancelled)` is `nil`, so a result from an operation the user replaced is never
      rendered as an absence of energy in their file. `InspectionPresentation` carries all three side by
      side, and the report, its warnings, its status and the `schemaVersion` 1 export are untouched.
      **Delivery is progressive, through one channel.** `InspectionUpdate` has a case per part and the
      flow model applies each to its own field, so whichever visualisation settles first is shown first
      and neither waits on the other — asserted in both orders. A third visualisation later means a new
      case, not a new parameter threaded through every call site.
- [x] 6.2 Discard stale results by operation identity, as the waveform already does.
      The same counter, now guarding **every** update rather than only the final outcome: a late report,
      waveform or spectrogram from a superseded operation is dropped before it is applied. The accepted
      re-entrancy rule is unchanged and now restated for two visualisations — during the inspection the
      state is `.working` and a second selection is ignored; once the report exists the inspection is
      over, only visualisations are pending, and a new selection supersedes them.
- [x] 6.3 Confirm boundary rule 10 still holds: no feature module gains a `URL` or an AppKit import.
      Re-checked by test now that the spectrogram crossed into a feature module: neither `FeatureImport`
      nor `FeatureAnalysis` imports AppKit, a media framework, Accelerate or the other feature, and
      neither mentions `URL` in any line of code. The composition root still translates between their
      vocabularies, exactly as it does for the waveform.

## 7. Presentation

- [x] 7.1 Draw the model in `FeatureAnalysis` with SwiftUI — no bitmap file, no dependency. Resizing
      redraws the existing model and never decodes or transforms again.
      One `Canvas`, one fill per cell, **no view per cell** — a view per cell would be up to 524 288
      SwiftUI views for one drawing. Each cell is filled flat with no interpolation between neighbours:
      a smoothed image would draw levels that were never measured, and across a cutoff an invented
      gradient is precisely the wrong artefact. `SpectrogramGeometry` maps the model onto whatever size
      it is given, so a resize re-runs only that arithmetic.
- [x] 7.2 Time horizontal, frequency vertical, **linear, from 0 Hz to the file's own Nyquist**, with no
      cropping at any sample rate. Legible marks at 16, 18, 20, 22 and 24 kHz plus the marks the sample
      rate requires above that.
      Band 0 is flipped to the bottom exactly once, in the geometry rather than the renderer. The marks
      are a **function of the file, never of the window**: a wider window shows the same marks further
      apart, so a reader cannot change the evidence by resizing. Asserted at 22.05, 24, 48 and 96 kHz —
      the axis always reaches Nyquist exactly, the marks stay between 4 and 14, and their spacing is
      constant, which is what makes the axis linear rather than logarithmic.
- [x] 7.3 A colour ramp with **strictly increasing luminance** — dark → deep blue → cyan → pale
      yellow/white — built natively, with no external library and no green-good/red-bad semantics.
      Five literal stops, deterministic on any display. Luminance rises strictly at every step, so the
      ordering survives in greyscale and under colour vision deficiency. A structural test asserts the
      ramp is never dominantly red or green. The clamp applies to the **colour coordinate only**: a
      value above 0 dBFS maps to the top of the ramp and `Spectrogram.values` is never written back.
- [x] 7.4 A **numeric legend** stating the −120…0 dBFS range. A gradient without a scale states nothing.
      Five printed ticks from −120 to 0, over swatches sampled from the same ramp the cells use, so the
      legend cannot drift from the drawing it explains.
- [x] 7.5 No interaction: no playback, zoom, scrubbing, selection or cursor; pointer and scroll activity
      leave the drawing and its data unchanged.
      The drawing is `allowsHitTesting(false)`. There is no gesture, no cursor, no selection, no tooltip
      and no state to change — the view holds none.
- [x] 7.6 The label states only what the drawing **is**, never what it implies: no "lossy", no
      "transcoded", no "fake", no probable encoder or bitrate, and never presented as a measurement.
      Swept across every string every state can produce, against both a claims list and an internals
      list. The sweep runs over **presented strings** rather than identifiers, so a technical value the
      product deliberately shows exactly as read is not confused with an internal name leaking out. The
      label says outright that the drawing does not, on its own, establish how the file was produced.
- [x] 7.7 State an absent or failed spectrogram in words rather than showing an empty area, and never as
      a defect of the file.
      Five states, five distinct statements — including the one group 4 made representable: a file
      shorter than one analysis window has audio and no columns, and says so. Absence, failure and
      too-short are asserted to be three different things; failure says it is a limit of producing the
      drawing rather than something read from the audio, and both add that the rest of the report is
      unchanged.
- [x] 7.8 Expose it as a **single** accessibility element with a composed label saying what it is.
      `accessibilityElement(children: .ignore)` over the whole section, with the drawing, the axes and
      the legend hidden beneath it. **The label is identical for 1 cell and for 524 288** — asserted —
      and carries what the eye gets from the axes and the legend: the range to the file's own Nyquist,
      the dBFS scale, and how many channels were combined.

## 8. The format matrix and tests

- [ ] 8.1 Domain unit tests: the 1024 × 512 caps, the frame→column mapping, the band arithmetic, and
      non-finite samples refused.
- [ ] 8.2 Analysis unit tests over synthetic signals: silence at the floor, DC, tones on and between
      bins with the scalloping tolerance the spike measured (±1.42 dB), two tones, impulse, values
      beyond `[-1, 1]` preserved, and **no normalisation** between two files 20 dB apart.
- [ ] 8.3 Cutoff tests: a brick-wall low pass at 16/18/19/20/22 kHz is located within one reduced band,
      at 44.1, 48, 96 and 192 kHz.
- [ ] 8.4 Reduction tests: a short transient survives folding, and the maximum is asserted to differ
      from a mean on the same input.
- [ ] 8.5 Channel tests: mono, identical stereo, tone in one channel only, different content per
      channel, opposite polarity — plus an assertion that **no spurious band** appears for two pure
      tones, which is the regression the time-domain control would fail.
- [ ] 8.6 Adapter integration over the format matrix — WAV, AIFF, ALAC, FLAC, AAC — one test per row,
      with **MP3 gated on FFmpeg** and **not** counted as coverage when skipped, exactly as
      `MP3WaveformEvidenceTests` does.
- [ ] 8.7 Container independence: the same audio as WAV and as FLAC yields **identical** models.
- [ ] 8.8 Determinism, chunk-size independence down to one frame, strict `frameLength`, bounded memory,
      and cancellation producing no partial model.
- [ ] 8.9 The report is unaffected: a file whose samples cannot be read yields the same properties,
      warnings and status, and the exported JSON is **byte-identical** with and without a spectrogram.
- [ ] 8.10 End-to-end: the existing flow test still walks the same pipeline, with a spectrogram present
      in one case and absent in the other. **No existing assertion is removed or weakened.**
- [ ] 8.11 Presentation tests over the model: the accessible label, the legend text, and that no
      interpretive vocabulary — lossy, transcoded, fake, bitrate, encoder, quality — appears anywhere on
      the spectrogram surface.

## 9. Migrating the waveform onto the shared seam — conditional

**This group has an explicit stop rule and may honestly end in a deferral.** It runs only after groups
2–8 are complete and green.

- [ ] 9.1 Reimplement the waveform's sample reading on `AudioDecoding`, leaving `WaveformGenerating`'s
      contract, its outcomes and its error space unchanged.
- [ ] 9.2 Confirm every existing waveform test passes **untouched**. Not adapted, not weakened, not
      re-baselined.
- [ ] 9.3 Confirm the two consumers stay independent: separate operations, separate cancellation, and
      neither depending on the other having been requested.
- [ ] 9.4 Confirm the envelope produced through the shared seam is **identical** to the one produced
      before the migration.
- [ ] 9.5 Confirm no UI change and no change to the flow's states.
- [ ] 9.6 **Stop rule.** If any of 9.2–9.5 cannot be met without coupling the consumers, weakening a
      test, touching the UI or materially widening this slice, **stop and defer the migration to its own
      change**, recording precisely what blocked it. Two reads remaining is a declared cost, not a
      failure of this slice.

## 10. Accessibility and manual validation

Nothing below may be marked done without actually performing it.

- [ ] 10.1 VoiceOver: the spectrogram is announced as a single element describing what it is, with no
      characterisation of the audio; an absent spectrogram is announced as unavailable.
- [ ] 10.2 Confirm every meaning the drawing conveys has a textual alternative, and that no meaning
      depends on colour alone.
- [ ] 10.3 Contrast: the drawing, its legend and its axis labels remain legible in light and dark
      appearance.
- [ ] 10.4 Confirm the colour ramp increases monotonically in luminance by viewing it in greyscale.
- [ ] 10.5 Look at a 96 kHz and a 192 kHz file and confirm the mostly-empty upper range reads as
      information rather than as a rendering fault.
- [ ] 10.6 Confirm by eye that nothing on the surface names an encoder, a bitrate, or a verdict.
- [ ] 10.7 Record the result in `docs/manual-validation-mvp.md` as a durable statement, stating plainly
      which checks were performed and which were not.

## 11. Gates and closure

- [ ] 11.1 Four gates green — `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test`,
      `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` — plus the Xcode app build.
- [ ] 11.2 Confirm the diff's scope: no new dependency, entitlements unchanged, the JSON exporter and
      the `schemaVersion` 1 contract byte-identical, `InspectionReport` and the property reader
      untouched.
- [ ] 11.3 Confirm Accelerate is imported only by `AudioInspectorAnalysis` (`check-boundaries.sh`
      rule 7) and that no Accelerate type appears in any port.
- [ ] 11.4 Delete `Spike/validate-static-spectrogram/` once ADR-0016 is Accepted and these tests cover
      its observations — the deletion criterion written into the spike report.
- [ ] 11.5 Decide ADR-0016's status from what was actually done (see 1.4), update `CURRENT.md`, and
      archive through `openspec archive` after merge, without editing the promoted specs by hand.
