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

- [ ] 2.1 Add `AudioDecoding` to `AudioInspectorDomain/Ports/` — a `Sendable` protocol taking
      `AudioFileReference` and yielding PCM in bounded, cancellable chunks with per-channel samples. No
      `AVAudioFile`, `AVAudioPCMBuffer`, `AVAudioFormat`, `NSError` or `OSStatus` in its signature.
      **Decide its exact shape here** — closure fold, `AsyncSequence`, or scoped accessor — from how
      cancellation and the security-scoped window compose (design.md, open question 1).
- [ ] 2.2 Add the spectrogram value type: `Sendable`, `Equatable`, carrying columns × bands of dBFS
      plus what the axes need. It holds no view size, no normalisation factor and no URL, and is **not**
      `Codable` — it never enters the `schemaVersion` 1 export.
- [ ] 2.3 Implement the column and band arithmetic as pure domain code, unit-testable with no file and
      no framework: at most 1024 × 512, the frame→column mapping a function of the file alone.
- [ ] 2.4 Give the spectrogram its own error space, **disjoint** from `InspectionError`,
      `PropertyFailure` and `WaveformError`. Represent an unusable frame count as an **absence**, not an
      error, and cancellation as its own outcome.
- [ ] 2.5 **Reject non-finite samples at the boundary**, as `WaveformBucket` does. The spike measured a
      single NaN silently collapsing 184 cells to the floor; the clamp must not be what hides them.
- [ ] 2.6 Decide whether a zero-frame file yields an empty model or no model, mirroring how
      `WaveformEnvelope` settled it (design.md, open question 3).
- [ ] 2.7 Decide whether a separate `SpectrogramGenerating` port is warranted or whether `AudioDecoding`
      plus a pure Analysis function is the whole seam (design.md, open question 2). Introducing a port
      with one consumer "because the architecture map names it" is the speculative abstraction this
      project refuses.

## 3. The Media adapter for PCM chunks

- [ ] 3.1 Implement `AudioDecoding` in `AudioInspectorMedia` with `AVAudioFile`, resolving the `URL`
      through the constructor seam exactly as the existing adapters do (ADR-0010). A fresh adapter per
      operation; no shared state, no registry.
- [ ] 3.2 **Consume exactly the reported frame count; never the buffer's capacity.** The reason is
      written beside it, as it is in the waveform adapter.
- [ ] 3.3 Verify the processing format before reading a sample — native deinterleaved float — and fail
      in a controlled way if it does not qualify, never constructing a contiguous pointer over
      interleaved data.
- [ ] 3.4 Bound the loop with `framePosition < length` and honour `Task.isCancelled` at chunk
      boundaries. Confine each `AVAudioFile` to the task that opens it.
- [ ] 3.5 Catch every Apple error and translate it into the domain's error space, classified by
      **scope** and never by SDK numeric code.
- [ ] 3.6 Confirm the adapter only reads: nothing writes, renames, moves or truncates the file.
- [ ] 3.7 Add the port fake to `AudioInspectorTesting` so Analysis and feature tests need no real file.

## 4. STFT and reduction in Analysis

- [ ] 4.1 Implement the STFT in `AudioInspectorAnalysis` with `vDSP.DiscreteFourierTransform`
      (`.complexReal`), FFT 2048, hop 512, Hann denormalised. **One setup per operation, reused for
      every frame of every channel** — recreating it per frame costs 10×.
- [ ] 4.2 Scale magnitude by `1 / windowSum` to absolute dBFS, reference 1.0, 20·log10, floor −120.
      **No normalisation of any kind.**
- [ ] 4.3 Transform each channel **separately** and combine by **maximum per bin, in the frequency
      domain**. Never combine samples before transforming. The result is a **combined** spectrogram: not
      a mono mix, not a downmix, and not named as one in code, tests or UI.
- [ ] 4.4 Process channels **sequentially**, sharing the one setup. No per-channel parallelism.
- [ ] 4.5 Reduce by **maximum** in both axes, never by mean.
- [ ] 4.6 **Discard the final incomplete window**; never zero-pad. Write the reason beside it.
- [ ] 4.7 Confine the transform setup: created and consumed inside one `nonisolated async` operation, no
      `@unchecked Sendable`, no stored property of a `Sendable` type, no global cache.
- [ ] 4.8 Confirm no Accelerate type appears in any signature Analysis exposes; `DSPSplitComplex`,
      `vDSP.*` and the setup stay inside.

## 5. Generation and orchestration

- [ ] 5.1 Produce the spectrogram inside the existing security-scoped window, as its **own operation**
      with its **own cancellation**, independent of the waveform's.
- [ ] 5.2 Confirm nothing changes in the sandbox story: no bookmark, no retained URL, no new
      entitlement, nothing persisted.
- [ ] 5.3 Order the work so the report is delivered first, then the visualisations; a global inspection
      failure skips the sample reads entirely.
- [ ] 5.4 Confirm cancelling one visualisation does not cancel the other.

## 6. Wiring and progressive state

- [ ] 6.1 Carry the spectrogram **beside** the report, with absence, failure and cancellation as
      first-class values. `InspectionReport`, `TechnicalProperties` and `Property` are untouched.
- [ ] 6.2 Discard stale results by operation identity, as the waveform already does.
- [ ] 6.3 Confirm boundary rule 10 still holds: no feature module gains a `URL` or an AppKit import.

## 7. Presentation

- [ ] 7.1 Draw the model in `FeatureAnalysis` with SwiftUI — no bitmap file, no dependency. Resizing
      redraws the existing model and never decodes or transforms again.
- [ ] 7.2 Time horizontal, frequency vertical, **linear, from 0 Hz to the file's own Nyquist**, with no
      cropping at any sample rate. Legible marks at 16, 18, 20, 22 and 24 kHz plus the marks the sample
      rate requires above that.
- [ ] 7.3 A colour ramp with **strictly increasing luminance** — dark → deep blue → cyan → pale
      yellow/white — built natively, with no external library and no green-good/red-bad semantics.
- [ ] 7.4 A **numeric legend** stating the −120…0 dBFS range. A gradient without a scale states nothing.
- [ ] 7.5 No interaction: no playback, zoom, scrubbing, selection or cursor; pointer and scroll activity
      leave the drawing and its data unchanged.
- [ ] 7.6 The label states only what the drawing **is**, never what it implies: no "lossy", no
      "transcoded", no "fake", no probable encoder or bitrate, and never presented as a measurement.
- [ ] 7.7 State an absent or failed spectrogram in words rather than showing an empty area, and never as
      a defect of the file.
- [ ] 7.8 Expose it as a **single** accessibility element with a composed label saying what it is.

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
