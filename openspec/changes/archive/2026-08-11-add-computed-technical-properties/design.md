# Design — computed technical properties

## 1. The question, and how it was answered

*"What additional technical properties should Audio Inspector expose, and which are objective facts
versus interpretation?"* This design answers it by first reading, exhaustively, where every existing
property comes from — no assumption stands that was not confirmed by reading
`AVFoundationAudioFilePropertyReader.swift` — then applying the same test to every candidate: **can this
be produced without a judgement call, and does removing the judgement call leave anything worth
reporting?** A second pass then re-audits every conclusion of the first draft against the project's own
existing ADRs and principles, before anything is committed — several conclusions below changed as a
result, and each says so.

## 2. Inventory of the eight existing properties

| Property | Exact source | Tier | Can be absent | Where it is absent |
| --- | --- | --- | --- | --- |
| `container` | `URL.resourceValues(.contentTypeKey)` → `UTType` | Inference from the OS's type system, never the container's own bytes | Always `.uncertain`, never `.available` (spike 0031/F found no direct signal) | Every format, by design |
| `duration` | `AVURLAsset.load(.duration)` → `CMTime` | Container/asset metadata | `.unavailable` (invalid/negative/indefinite), `.uncertain(0)` (reported zero) | Empty/truncated files |
| `sampleRate` | ASBD `mSampleRate` | Codec/stream | No track, no format description, non-integer Hz | Files with no audio track |
| `channelCount` | ASBD `mChannelsPerFrame` | Codec/stream | Same as above | Same |
| `bitDepth` | ASBD `mBitsPerChannel`, **only when `mFormatID == kAudioFormatLinearPCM`** | Codec/stream | `.unavailable` for every non-PCM format (not yet split into `.unsupported`; spike 0031/D did not validate the lossy/lossless-compressed distinction) | All lossy and compressed-lossless codecs today |
| `codec` | ASBD `mFormatID` → FourCC token | Codec/stream | No ASBD, zero format id | Files with no audio track |
| `declaredBitrate` | **No API produces this value.** `declaredBitrate(from:)` returns `.unavailable` unconditionally | — | Always | Every format, unconditionally |
| `estimatedBitrate` | `AVAssetTrack.load(.estimatedDataRate)` → `Float` | Framework estimate | Always `.uncertain`; the value itself is absent (`nil`) when the rate is `0`, negative, non-finite or fractional | PCM (WAV/AIFF): the API reports `0`, so no usable number ever appears |

The load-bearing fact this table proves: **`declaredBitrate` is not a property that sometimes fails to
read — it is a property with no data source in this codebase**, and for PCM, `estimatedBitrate` is
equally empty in practice. Two of eight fields carry no number at all for a large share of real files.

## 3. Bitrate, in full

**What `declaredBitrate` means today:** a nominal rate the container/codec *itself* declares, with no
self-computation (ADR-0012 tier 3). No such source exists among the evaluated APIs, so it is always
`.unavailable` — an absence of capability, not a read failure, so never `.failed`.

**What `estimatedBitrate` means today:** the framework's own estimate of the track's data rate, always
carried as `.uncertain` by contract (criterion 3.5 of `add-basic-audio-file-inspection`). For PCM this is
`0`, mapped to `.uncertain(nil)` — an estimate that estimates nothing.

**Can a real average bitrate be computed mathematically? Yes, unconditionally, from data already read:**

```
averageFileBitrate = sizeBytes × 8 ÷ duration
```

- `sizeBytes: Int?` — `AudioFileReference.sizeBytes`, read via `URLResourceValues.fileSize` in
  `AudioFileReferenceMapper.swift`. Filesystem fact, not an AVFoundation read.
- `duration: Property<Double>` — already inside `TechnicalProperties`.

**Preconditions for the computation to exist:** `sizeBytes != nil` (best-effort; already surfaces
`metadata_size_unavailable` when absent) and `duration` is a clean, positive, confirmed value — not
`.unavailable`, not `.uncertain(0, ...)` (would divide by zero), not `.failed`.

**What it measures, exactly — audited claim by claim:**

| Claim | True? |
| --- | --- |
| Audio payload alone | **No** |
| Whole file on disk | **Yes** — every byte `URLResourceValues.fileSize` counts |
| Container headers (RIFF/WAVE, MP4 atoms, FLAC STREAMINFO, …) | **Included** in the numerator |
| Metadata/tags (ID3v2, APEv2, ID3v1 trailer) | **Included** |
| Embedded artwork | **Included** |
| Padding/seek tables | **Included** |

**Renamed from `calculatedAverageBitrate` to `averageFileBitrate`, on this evidence, not on taste.** The
first draft's precision claim — *"for a typical file without embedded art this overhead is bytes against
megabytes: negligible"* — understated a real, common case and is corrected here: embedded cover art is
**routine**, not exotic — a purchased or iTunes-tagged file commonly carries a 200 KB–5 MB embedded
image. A concrete number: a 3 MB embedded cover on a 3-minute (180 s) track adds `3,000,000 × 8 ÷ 180 ≈
133,000` bits/s to whatever the audio payload alone would compute to — on a file whose real encoded rate
is 320 kbps, that is a **~40% inflation**, not a rounding error. Calling this field *bitrate* without a
qualifier invites exactly the reading ADR-0012 already warned against — mistaking a computed
approximation for a measured fact about the stream. `estimatedBitrate` already carries a hazard like this
implicitly (an API-provided guess); `averageFileBitrate` needed a name that keeps the hazard visible at
the call site, not only in a doc comment nobody reading raw JSON will see. Other candidates and why they
lost: `calculatedFileBitrate` drops "average," which is the correct word for a rate obtained by dividing
a total by a duration and should stay; `fileAverageDataRate` breaks the shared `…Bitrate` suffix that lets
a reader immediately group this with `declaredBitrate`/`estimatedBitrate` as the three bitrate-shaped
facts, for no added clarity. `averageFileBitrate` keeps the family resemblance and puts the one word that
matters — *File*, not *stream* — directly next to *Bitrate*, where it cannot be silently dropped in a
sentence the way a doc-comment caveat can be. The `.uncertain` reason string itself will additionally
spell out headers/tags/artwork explicitly, not just say "an estimate" (task 2.3).

**Precision and its limit, stated exactly:** the numerator is the **whole file**, not the audio payload,
for the reasons above, and **nothing in this computation can tell audio bytes from artwork bytes apart**
without parsing the container — explicitly out of scope per ADR-0012. This is exactly the reasoning
ADR-0012's own rejected alternative already gives for never promoting a computed rate to `.available`:
*"reporting it as available would invent precision."* This design does not revisit that; it exercises it,
and states it more concretely than the first draft did.

**Where the two already-available facts currently fail to meet:** `sizeBytes` lives on
`AudioFileReference` (sibling metadata), `duration` lives inside `TechnicalProperties`.
`AVFoundationAudioFilePropertyReader.readProperties(of file:)` already receives the whole
`AudioFileReference` — `sizeBytes` is already in scope at the call site — but `technicalProperties(from:)`
only takes the narrower `LoadedAudio` and never sees it. Closing this is plumbing, not a capability gap:
threading `file.sizeBytes` one level further is the only wiring this needs.

## 4. `declaredBitrate` — audited for survival, not assumed

Always empty is not, by itself, a reason to remove a field — but it is also not a reason to keep one
without checking. Tested against this project's own stated discipline (`docs/project-principles.md` #2
"no arbitrary score," #12 "grow only at real seams — never speculatively") rather than against "it was
already there":

- **It has a real producer.** `declaredBitrate(from:)` is a function that runs on every inspection and
  deterministically returns `.unavailable(reason: nil)` today. That is not "no code path assigns this" —
  it is the `Property<Value>` model (ADR-0008) working exactly as designed: absence is a first-class,
  reported state, not a gap. The question "does this have a producer" has a concrete, checkable answer,
  and the answer is yes.
- **ADR-0012 already treats it as a permanent conceptual tier**, not a placeholder: its reliability-tiers
  table names `declaredBitrate` explicitly and gives the reason it is currently empty (no Apple API
  guarantees a directly-declared value) — a reason about the *platform today*, not about this feature
  being unfinished. A real source is plausible and simply unvalidated: MP3's own Xing/VBRI header
  commonly carries an explicit average-bitrate field, and ADR-0012 names AudioToolbox as "a fallback
  under evaluation" that might one day surface something like it. Removing the field would foreclose a
  real, named future producer, not just tidy up a currently-idle one.
- **Removal is not free — it is a bigger, more disruptive change than keeping it.** `declaredBitrate` is
  already a shipped `schemaVersion` 1 wire field. Removing it would be a **non-additive** change to a
  contract this project's own convention (ADR-0009, `docs/json-schema-v1.md`) treats as additive-only.
  Keeping an honestly-empty field costs nothing; removing it costs a schema-evolution exception nothing
  here justifies.

**Decision: Option A — keep it, unchanged**, with one small, low-risk refinement worth doing alongside
this change rather than a separate one: give `declaredBitrate(from:)`'s `.unavailable` case a real
`reason` string (today it passes `nil`) now that the reason is fully understood, rather than leaving a
`nil` a future reader has to re-derive from source. This is a documentation-quality improvement, not a
structural or naming change, and is listed as an optional task rather than forced.

## 5. `estimatedBitrate` — renaming closed, not left open

The first draft left `estimatedBitrate` → `frameworkEstimatedBitrate` as an open question "for whoever
implements this." That was avoiding the decision, not making one; closed here with the actual cost
measured across every surface it touches, because — unlike `averageFileBitrate`, which does not exist
yet — **`estimatedBitrate` is a live, shipped field today**, not a proposal:

| Surface | Cost of renaming |
| --- | --- |
| Domain (`TechnicalProperties.estimatedBitrate`) | Small in isolation — one field and one reader method |
| **JSON export** | **High** — `estimatedBitrate` is an already-shipped `schemaVersion` 1 wire key. Renaming it breaks every existing consumer of a contract this project's own convention treats as stable and additive-only (ADR-0009); this is not a minor edit, it is the exact kind of contract change the version number exists to prevent |
| Tests | Real but mechanical — property-reader tests, comparison tests (`FileComparison.estimatedBitrate`), export isolation tests, presentation tests all reference it today |
| Two-file comparison feature | `FileComparison.estimatedBitrate`, `ComparisonFormatter`'s row set, and the "Estimated bitrate" row label all reference the current name |
| UI | Low — the user-facing label ("Estimated bitrate") can be adjusted independently of the Swift/JSON identifier if ever needed, at no coupling cost |
| Documentation | `docs/json-schema-v1.md` documents the current key as part of the stable contract |

**Decision: do not rename.** The only benefit is a marginally more self-describing Swift identifier once
a second estimate exists — and that benefit is already delivered by `averageFileBitrate`'s own name,
which needs no help from its sibling's name to be unambiguous. The cost is a breaking change to a shipped,
versioned wire contract for a purely cosmetic gain. This fails the "if the rename doesn't earn enough
value, don't do it" test outright; it is not a close call.

## 6. New properties considered, one by one

For each: how it is computed, whether it needs a full sample pass, whether it needs an FFT, whether it
depends on format, and whether the result is a fact or a judgement.

| Property | Computation | Full sample pass | FFT | Format-dependent | Objective | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| Average file bitrate | `sizeBytes × 8 ÷ duration` | No | No | No | Yes | **In scope** |
| Peak sample | `max\|sample\|`, per channel | Yes | No | No | Yes | **In scope** |
| DC offset | mean sample value, per channel | Yes | No | No | Yes | **In scope** |
| RMS | `sqrt(mean(sample²))`, per channel | Yes | No | No | Yes | **In scope** |
| Clipped samples | count of `\|sample\| ≥ 1.0`, threshold a named, versioned constant | Yes | No | No | Yes, given a fixed published threshold | **In scope** |
| Crest factor | `peak ÷ RMS` in dB | No — derived from the two already computed | No | No | Yes | **Re-audited below — still deferred** |
| True peak | oversampled peak (≥4×, ITU-R BS.1770/EBU R128) | Yes | No (interpolation filter, not a transform) | No | Yes | Named, **not designed here** — ADR-0006 already governs it |
| Significant max frequency | highest frequency with energy *meaningfully above the local noise floor, over time* — not a raw bin scan | Yes (via STFT) | **Yes** | No | Yes, given a fixed published noise-floor threshold | Named, **not designed here** — see §10 |
| Lowest observed frequency | analogous, low end | Yes | Yes | No | Weak | **Rejected** — no product need is on record anywhere in this repository |
| "Dynamic range" (unscoped) | ambiguous: LRA, TT-DR, and windowed peak-to-RMS are different, disagreeing metrics | varies | varies | No | **No, as a single field** | **Rejected as named** — ADR-0006 already forbids a single dynamic-range truth |

**Cost, from evidence already in this repository, not from estimation.** Peak/DC-offset/RMS/clipping are
the same shape of operation as `PCMChunk.isProvablyAllFinite` — one accumulation per sample, no
transform. That exact operation is measured in this codebase: a scalar loop cost **7.2 s** for a
ten-minute stereo file; the SIMD8 form already in production use brings it to a fraction of a second.
Significant-max-frequency would reuse the STFT path measured at **0.9–1.8 s** for a ten-minute, 68 MB file
(group 12) — see §10 for why it is still not designed here despite that infrastructure already existing.
Neither number is invented for this document.

## 7. Two rejections, argued rather than asserted

**Lowest observed frequency.** The high-frequency counterpart has a real, named use — detecting a lossy
codec's cutoff or an ADC's band limit, both already discussed in `analysis-methodology.md` and the
spectrogram's own group 8 findings. Nothing in this project's vision, roadmap or methodology document
motivates a symmetric low-frequency figure, and ordinary program material rarely carries meaningful
content near the bottom of the band in a way a listener or a forensic reader would act on. Calculable;
not designed, for lack of a use.

**Generic "dynamic range."** ADR-0006 already states the rule this would break: *"Where multiple
dynamic-range metrics exist, present them side by side and explain differences — never a single
'dynamic range' truth."* LRA (EBU R128), TT-DR and a windowed peak-to-RMS figure are three different,
sometimes disagreeing numbers. A field simply named `dynamicRange` would present one of them as *the*
answer, which is the exact shape of the single-aggregate mistake this project refuses elsewhere (no
comparison score, no quality score). If dynamics reporting is ever built, it is built as the *named*
metrics the roadmap already schedules for Phase 3, each labelled by its own methodology.

## 8. The PCM level metrics, made precise

Vague terms are not acceptable for four properties that will each become a public field. Each is fixed
here exactly.

**Global vs per-channel: both, not a choice.** Per-channel is the canonical, stored representation —
consistent with `PCMChunk.channels` and `WaveformEnvelope`'s own per-channel buckets, and necessary
because a real asymmetry (a DC bias on one channel from a capture fault, one channel clipping and not the
other) is exactly the kind of fact collapsing to one number would hide. A whole-file "overall" figure is
additionally exposed, **derived by a fixed formula, not a second measurement**:

- **Overall peak** = `max` of the per-channel peaks (trivially well-defined).
- **Overall RMS** = `sqrt(sum of all samples' squares across every channel ÷ total sample count across
  every channel)` — every individual sample weighted equally regardless of which channel it came from.
  This is **not** the same number as an average of the per-channel RMS values, and the difference must be
  stated in the type's own documentation so no consumer computes it the wrong way.
- **Overall DC offset** = the same "treat every channel's samples as one combined sequence" mean.
- **Overall clipped-sample count** = the plain sum of the per-channel counts.

All four combination rules are closed-form arithmetic over already-computed per-channel values — no
second pass over the file, no judgement call.

**Units, exactly:**
- **Peak and RMS: dBFS** (`20 × log10(|value|)`), matching `analysis-methodology.md`'s own stated unit
  for both. Reusing the spectrogram's already-established **−120 dBFS floor** for the zero/near-zero case
  rather than inventing a second floor convention in the same application. A peak can be **positive**
  dBFS: `PCMChunk`'s own contract keeps a sample beyond `-1...1` exactly as read rather than clamping it,
  so a genuinely out-of-range float sample must be allowed to report a positive dBFS peak — this is
  inherited behaviour, not a new design choice, and must be called out in the field's own documentation
  so a positive value is not mistaken for a bug.
- **DC offset: linear**, not dB — a mean sample value can be negative and sits naturally near zero, where
  a decibel scale has no good behaviour. `analysis-methodology.md` itself only specifies dBFS for peak
  and RMS, never for DC offset.
- **Clipped-sample count: a plain `Int`.** A percentage is a trivial presentation-layer derivation from
  this count plus the already-known frame count and is not stored redundantly.

**Zero frames.** `PCMStreamDescription` already treats a frame count of zero as "a complete, honest
answer," not an error. The level metrics for such a stream follow the exact precedent
`WaveformEnvelopeAccumulator` already sets for "never covered" versus "covered and silent": with **zero**
samples, peak/RMS/DC-offset are **not computable** (division by zero, an undefined maximum) and the type
must be able to say so distinctly from "computed, and the value is zero" — the same distinction that
prevents a genuinely silent file from being confused with one that could not be measured at all.

**N channels.** No channel-count assumption anywhere; the accumulator holds one running state per
channel, for however many the stream reports, mirroring `PCMChunk.channelCount`'s own generality.

**Samples beyond `|1|`.** Kept and reported exactly as decoded, never clamped — inherited directly from
`PCMChunk`'s own explicit contract, not a new decision this design is making.

**Clipping threshold, exactly.** `|sample| ≥ 1.0` (full scale on the domain's own normalized amplitude
scale) — the simple case `analysis-methodology.md` calls "consecutive full-scale samples," matching the
roadmap's own "basic clipping" framing for this increment. The document's own "near-0 dBFS run detection"
refinement is real but is **not** part of this slice: it needs a second, separate threshold and a
consecutive-run rule, which is more than "basic," and belongs with the roadmap's own Phase 3 master-
analysis work rather than smuggled into an MVP whose whole point is staying small.

**Is the threshold configurable?** No — **never user-configurable.** It is a **named constant tied to the
analysis engine version**, exactly the pattern ADR-0006 already established for loudness thresholds
(criterion: "every threshold/constant is a named constant tied to the engine version; changing any bumps
the version"). This follows from this project's own principle #7 (reproducible, versioned results), not
from a preference — a user-adjustable analysis threshold would make two runs of the same file
non-reproducible by design, which principle #7 rules out directly.

**One pass, confirmed.** Peak (running max), RMS (running sum of squares), DC offset (running sum), and
clipped count (running comparison) are four independent, O(1)-per-sample accumulations over the *same*
stream of samples, with no cross-sample dependency and no look-ahead — exactly the shape
`WaveformEnvelopeAccumulator`'s min/max fold already proves works this way. All four fit in one
accumulator, one pass.

## 9. `SignalLevelMetrics` — the name, defended rather than assumed

Rejected alternatives, and why: `PCMStatistics` and `SampleStatistics` name the **implementation detail**
(PCM is the wire shape `AudioDecoding` moves audio in) rather than the **domain concept** a report reader
cares about — exactly the mistake this audit was asked to avoid, and neither `WaveformEnvelope` nor
`Spectrogram` names itself after PCM despite being built from exactly the same chunks. `AudioSignalMetrics`
is broader than what this type actually holds and would invite unrelated future additions (stereo
correlation, spectral centroid — real future metrics, but not level metrics) to be added here simply
because the name does not exclude them, which principle #12 ("grow only at real seams") argues against.

**`SignalLevelMetrics` is kept.** "Level metering" is an established term of art in audio engineering
(VU/PPM meters are literally called level meters) naming exactly this family — peak, RMS, DC offset,
clipping, and, later, true peak all belong to *level*, while spectral or stereo metrics do not. The name
scopes the type correctly for what it holds today and for the one named future addition (true peak) that
belongs beside it.

## 10. Where DSP-derived properties live, and how they are produced

`TechnicalProperties.swift`'s own first line: *"Basic, metadata-level technical properties of an audio
file — **no DSP**."* That is an existing boundary, not a description available to relax. Peak, RMS, DC
offset and clipping all require decoding every sample, which is DSP by this project's own definition
(`AudioInspectorAnalysis` is the only target with signal processing; `AudioInspectorDomain`, where
`TechnicalProperties` lives, imports nothing). So `SignalLevelMetrics` lives beside the report, a peer of
`WaveformEnvelope`/`Spectrogram`, never a member of `TechnicalProperties`.

**Ownership by layer:**
- **Domain (`AudioInspectorDomain`)**: `SignalLevelMetrics` and `SignalLevelMetricsAccumulator` — pure
  value type and pure fold, no import, mirroring `WaveformEnvelopeAccumulator` exactly. Stays here unless
  measurement shows pure Swift cannot keep pace, in which case only the *accumulation loop* moves to
  Analysis, not the type.
- **Analysis (`AudioInspectorAnalysis`)**: only entered if group-12-style measurement (a real ten-minute
  file, an unoptimised build first) shows the pure-Swift accumulator is too slow — not decided by default,
  decided by a number, exactly as group 12 did for the spectrogram's own reduction loops.
- **App (`AudioInspectorApp`)**: orchestrates a **third independent operation**, alongside the waveform's
  and the spectrogram's, with its own cancellation.
- **Feature**: presentation only — words, units, no verdict, no colour-only meaning.

**Does this need a third full-file read? Yes — and that is the consistent choice, not a new risk.**
ADR-0016 already decided this question in principle: *"More than one analysis reads the same audio... and
each runs as its own operation with its own cancellation... A single shared pass producing several
results was considered and rejected."* A third consumer applies the same, already-accepted answer a third
time; it does not reopen the question.

**Is the cost acceptable?** Yes, quantified rather than assumed: the marginal cost of a third pass is
dominated by one more full-file **decode** — the same I/O-and-codec cost the waveform pass already pays
today without complaint — plus a reduction that is *cheaper* than either existing consumer (pure
accumulation, no bucket-boundary math, no FFT). No shared-read strategy is introduced by this change; none
is needed.

**Does it piggyback on the waveform's own read?** No — audited and rejected specifically, not merely
skipped. The waveform does **not** use the shared `AudioDecoding` port at all: CURRENT.md records that its
migration onto that seam was deliberately deferred, for real, named incompatibilities (a decoding error
space the shared port cannot represent, a non-positive-sample-rate case the waveform currently handles
differently, and existing tests tied to its own read path) — **declared debt, not an oversight, and not a
decision this change may quietly reverse.** Hooking `SignalLevelMetrics` into the waveform's own separate
generator would couple a new, independent concern to that same debt, make the eventual migration *harder*
by adding a second dependent, and reintroduce exactly the shared-pass coupling ADR-0016 already rejected
in principle. **Decision: Option A — an independent operation over the shared `AudioDecoding` port**,
structurally identical to how the spectrogram already uses it. Options B (reuse the waveform's generator)
and C (a new shared-composition abstraction) are rejected for the reasons above; option D (defer the
decision) does not apply — the decision is made, not deferred.

`averageFileBitrate` is the opposite case: pure arithmetic on two values already read from metadata,
requiring no sample access at all. It stays inside `TechnicalProperties`, inside the existing "no DSP"
boundary, exactly beside `declaredBitrate` and `estimatedBitrate`.

## 11. Significant max frequency — confirmed out of scope, and why more firmly than before

Re-examined directly against the question "is this a simple objective reduction over the existing
spectrogram, or a real heuristic": it is the latter, and more so than the first draft credited. A naive
"highest FFT bin with non-zero energy" is close to useless — dither and quantisation noise put non-zero
energy in nearly every bin up to Nyquist on almost any real file. `analysis-methodology.md`'s own
definition requires energy *"meaningfully above the local noise floor, measured over time"* — which
needs, at minimum, a noise-floor estimation method, a margin (in dB) above it, and a persistence rule
across STFT frames, each a named constant this project's own versioning discipline (ADR-0006's pattern)
would require to be fixed and disclosed. That is multiple linked design decisions, comparable in weight to
what ADR-0006 already did for true peak — not a one-line reduction. **It is not designed here, and this
audit's own re-check makes that exclusion firmer, not weaker.**

One clarification worth recording for whoever picks this up later: when it is designed, it needs **no new
file read at all** — it is a pure post-processing step over the `Spectrogram` model the existing slice
already produces after inspection, unlike `SignalLevelMetrics`, which does need its own decode pass. That
cost difference is worth knowing before scoping that future change.

## 12. True peak and crest factor — re-confirmed, not just repeated

**True peak** stays out of this slice, unchanged from the first draft: it needs a real interpolation
filter (Accelerate/vDSP), its methodology is already fixed by ADR-0006, and its constants are explicitly
"pending implementation" there — implementing it belongs to a change that can devote its own attention to
that filter and its cross-check against FFmpeg, per ADR-0006 itself.

**Crest factor** — re-audited, not simply left where the first draft put it. It is mathematically free
once peak and RMS both exist (one subtraction in dB), and unlike "dynamic range" it has exactly one
standard definition, so ADR-0006's "never a single truth" objection does not apply to *it* directly.
The reason to still defer it is different: exposed alone, out of the context the roadmap's own Phase 3
loudness suite would give it (LUFS, LRA, and crest factor presented together, each labelled), a bare
crest-factor number invites exactly the kind of out-of-context "how compressed/dynamic is this master"
reading `analysis-methodology.md`'s own "separating the four qualities" section warns against — the same
shape of risk as the generic "dynamic range" field, even though the metric itself is unambiguous. Free to
compute is not the same question as ready to present responsibly. **Deferred, matching the roadmap's own
Phase 3 placement — not added to this slice.**

## 13. The MVP this design commits to, and nothing beyond it without new evidence

Five properties, and no more: `averageFileBitrate`, peak, RMS, DC offset, clipped-sample count. Everything
else considered in this document is either rejected outright (lowest observed frequency, unscoped dynamic
range) or named and deferred with its own reason (true peak, significant max frequency, crest factor).
`declaredBitrate` and `estimatedBitrate` are audited and kept exactly as they are.
