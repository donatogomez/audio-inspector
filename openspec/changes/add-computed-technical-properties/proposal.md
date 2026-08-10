## Why

An audit of the current technical-property model (triggered by a direct question: *which additional
technical properties should Audio Inspector expose, and which are objective facts versus
interpretation?*) found two concrete, evidenced gaps rather than a vague "add more metrics" ask.

**The first gap is a hole in coverage that already contradicts the model's own intent.** `declaredBitrate`
has no source anywhere in this project — Spike 0031/G found none among the evaluated AVFoundation APIs,
and the reader's own code says so outright (`declaredBitrate(from:)` always returns `.unavailable`).
`estimatedBitrate` comes from `AVAssetTrack.estimatedDataRate`, which is `0` for PCM — so for WAV, AIFF,
FLAC and ALAC today, **there is no bitrate number of any kind**. Yet the two facts needed to compute one —
`AudioFileReference.sizeBytes` and `TechnicalProperties.duration` — are already read, on every
inspection, today. ADR-0012 already considered computing a bitrate from size and duration and did not
reject the computation, only the idea of reporting it as `available`: *"it is an estimate; reporting it
as available would invent precision... it is always uncertain."* This proposal takes up exactly that
already-approved shape.

**The second gap is a real product need already named in `docs/roadmap.md` and
`docs/analysis-methodology.md`, not started.** Phase 1b of the roadmap names "sample peak, RMS, DC
offset, basic clipping" as the very next increment after the current slices; the methodology document
already carries their reference definitions. Nothing about them has been designed against the actual
`AudioDecoding` port and `TechnicalProperties`'s own documented boundary (**"no DSP"**) until now.

This proposal is the contract for both, following the same discipline ADR-0008/ADR-0012 already set: no
invented values, no aggregate, evidence kept apart from interpretation, and a computed number never
dressed up as a declared one.

## What Changes

- **`averageFileBitrate`** (renamed from an earlier `calculatedAverageBitrate` draft, on evidence — see
  `design.md` §3) — a new `Property<Int>` field inside `TechnicalProperties`, computed from
  `sizeBytes × 8 ÷ duration`. Metadata-only arithmetic (no DSP, no decoding), so it stays inside the
  existing "no DSP" boundary of `audio-file-inspection`. **Always `.uncertain` when computable, never
  `.available`** — the same honesty rule ADR-0012 already applies to `estimatedBitrate`, for the same
  reason: the numerator is the *whole file* (headers, tags, and commonly a multi-megabyte embedded cover)
  divided by duration, not the audio payload alone, and a 3 MB cover on a 3-minute track alone can inflate
  the figure by roughly 130 kbps — not a rounding error.
- **`declaredBitrate` and `estimatedBitrate` audited and kept exactly as they are** — a candidate removal
  and a candidate rename were both considered and both rejected with a quantified cost, not left as an
  afterthought (`design.md` §4–5).
- **A new capability, `audio-signal-level-metrics`.** Peak sample, DC offset, RMS and a clipped-sample
  count, each fully objective, each computed by one pass over decoded PCM with no FFT, each precisely
  specified — units, per-channel and derived overall values, zero-frame behaviour, and a named, versioned
  clipping threshold (`design.md` §8). These do **not** join `TechnicalProperties` — its own contract
  forbids DSP — and instead become a new domain value type, `SignalLevelMetrics`, living beside the report
  in the shape `WaveformEnvelope` and `Spectrogram` already established, produced by its own independent
  read over the shared `AudioDecoding` port (not the waveform's separate, deliberately-unmigrated path).
- **A new ADR** fixing two permanent decisions: where a DSP-derived property may live relative to
  `TechnicalProperties`, and that a computed/estimated bitrate is never conflated with a declared one,
  now that there are two independent estimates rather than one.
- **Named, not started:** true peak (already governed by ADR-0006, needs its own oversampling
  implementation), crest factor (mathematically free once peak+RMS exist, deferred anyway to avoid an
  out-of-context "how dynamic is this master" reading), and a noise-floor-relative "significant max
  frequency" (needs its own methodology decisions, not a simple reduction — `design.md` §11). All three
  are real, evidenced candidates; none is designed in this slice.

## What This Deliberately Does Not Do

- **No implementation.** This change is the contract — proposal, design, tasks and the spec deltas —
  exactly as `add-two-file-technical-comparison` began. `Sources/` and `Tests/` are untouched by this
  change; every task below stays open until a future session picks it up.
- **No "Dynamic Range" field.** ADR-0006 already rejected a single dynamic-range truth — multiple
  legitimate, disagreeing definitions exist (LRA, TT-DR, windowed peak-to-RMS). A field named generically
  `dynamicRange` would smuggle a methodology choice in as if it were a plain fact. Deferred to the full
  loudness suite (roadmap Phase 3), where each named metric can be presented beside the others it might
  disagree with.
- **No "lowest observed frequency."** Unlike the high-frequency case (a real, named product need — the
  significant-max-frequency work already on the roadmap), no document in this project motivates a
  low-frequency counterpart, and ordinary program material rarely carries anything below it worth
  reporting. Not designed.
- **No true peak or spectral work implemented.** Both are named as follow-ups with their reasons, not
  silently dropped, matching how `add-two-file-technical-comparison`'s group 9 named its own deferred
  scope.
- **No rename of `estimatedBitrate` and no removal of `declaredBitrate`.** Both keep meaning exactly what
  they mean today and keep their current wire keys; only `declaredBitrate`'s empty `.unavailable` case may
  gain a real `reason` string as a documentation-quality refinement, never a semantic change.
- **No new port.** `SignalLevelMetrics` is produced by a new, independent consumer of the *existing*
  `AudioDecoding` port — the same one the spectrogram already uses — not a new decoding abstraction.

## Impact

- Affected capabilities: `audio-file-inspection` (one field added to an existing requirement), plus a new
  `audio-signal-level-metrics` capability.
- Affected code (when implemented, not in this change): `TechnicalProperties`,
  `AVFoundationAudioFilePropertyReader`, the new `SignalLevelMetrics` value type and its accumulator
  (consuming the existing `AudioDecoding` port as a third independent operation), the presentation layer,
  and `docs/json-schema-v1.md` for the new wire fields.
- No change to `schemaVersion` 1's existing fields; new fields are additive only, per ADR-0009 — the new
  bitrate field joins `technicalProperties`, and `SignalLevelMetrics` fits the schema's own already-
  anticipated, still-unused `measurements` object.
