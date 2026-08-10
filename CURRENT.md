# Current working context

> **Contract — read before editing this file.**
>
> - **A single, overwritable snapshot** of the *current* working focus — **not a log.** Overwrite it in
>   place; never append history (git owns history).
> - **Intent only.** It records what is being worked on and *why* — the narrative no tool captures. It
>   is **never a source of truth** and must never contradict git, OpenSpec, or the ADRs. If it disagrees
>   with them, **they are right and this file is stale.**
> - **May be completely empty** (nothing under the template) when `main` is the latest and no thread is
>   open. **An empty `CURRENT.md` is the correct steady state**, not a gap to fill.
> - **Never put here:** task checklists (→ `openspec/changes/<name>/tasks.md`), branch/commit facts as
>   truth (→ git), decisions (→ `docs/adr/`), explanations (→ `docs/` / `OVERVIEW.md`), rules
>   (→ `CLAUDE.md`).
> - **To learn the real state**, do not trust this file — run `openspec list` and `git status` (see the
>   session protocol in `CLAUDE.md`).

---
**Focus:** `add-static-spectrogram-visualization` — the contract, the evidence behind it and **the whole
domain contract** are integrated; the previous documentation snapshot is published. Group 0 is closed: a
spike that anyone can re-run measured every constant before a single requirement was written, and three
of its findings changed the design rather than confirming it. **Groups 2 to 5 are complete**: the
domain holds `AudioDecoding`, `PCMStreamDescription`, `PCMChunk`, `PCMChunkDisposition`,
`AudioDecodingError`, `SpectrogramGridMapping` and `Spectrogram`; `AVFoundationAudioDecoder` implements
the port over real files with a fake beside it in `AudioInspectorTesting`; `AudioInspectorAnalysis`
holds the **STFT accumulator**, its first real contents; and `SpectrogramGeneration` composes
**decode → accumulate → finish** inside the security-scoped window the inspection already owns,
yielding *available*, *unavailable*, *failed* or *cancelled*. **Group 6** carries that result **beside**
the report: report, waveform and spectrogram travel as three parallel values, delivered progressively
through one `InspectionUpdate` channel so whichever visualisation settles first is shown first and
neither waits on the other. Every update is guarded by the operation identity, so a result from a
replaced operation reaches nothing. The spectrogram's visible states are *loading*, *available*,
*unavailable* and *failed* — **cancellation settles into none of them**, because a generation the user
replaced must never be shown as a limitation of their file. The waveform and the spectrogram remain
entirely independent operations. **Group 7 draws it**: the static spectrogram is now visible inside the
report, time horizontal, frequency linear to the file's own Nyquist and never cropped, energy as a
perceptual ramp with a numeric **−120…0 dBFS** legend, every non-drawn state said in words, and an
accessible contract on the drawing. Its isolation is demonstrated rather than asserted — the drawing
touches neither the JSON nor the export, and a spectrogram that is absent, failed or cancelled degrades
nothing about the inspection. **Group 8 ran the whole capability against the production pipeline** —
decoder → generation → model — over real files rather than scripted chunks: **WAV, AIFF, ALAC, FLAC and
AAC**, each opening, describing its own stream, staying inside the caps, keeping the axis at its own
Nyquist and leaving the source byte-identical. **MP3 is covered by local, FFmpeg-gated evidence** that CI
skips, and a skip is stated in the test itself to be no coverage at all. A known band limit is
**observable** — present below, gone above, in the same band whatever lossless container carries it, and
surviving an MP3 being rewrapped as WAV — while remaining an observation and never a verdict. The
report's isolation is confirmed once per format: a spectrogram genuinely produced changes no property,
no warning, no status and no exported byte.

**What group 5 forced on the seam.** The accumulator needs the stream's shape *before* the first chunk,
and the port only returned it after the whole decode. Buffering, decoding twice and taking the frame
count from the report were all worse, so the description now travels **with each chunk** — which also
makes it impossible to receive audio without knowing what stream it came from.

**Two things group 4 settled that the spike had not.** vDSP packs **DC and Nyquist into the same
element** of a real-to-complex transform, so energy at Nyquist was landing in the *bass*; both ends are
now unpacked into their own bins and the frequency axis reaches Nyquist literally. And discarding the
incomplete final window means a clip **shorter than one window** has audio and no complete window — it
now yields a valid spectrogram of **zero columns**, where the previous contract could not represent it
at all. Neither escape the spike used was taken: no invented column, no padded window.

**What the decoder's negative control taught, still worth carrying forward:** clamping a read with
`min(frameLength, remaining)` makes the `frameLength` invariant *unobservable*, because a short read
only ever happens on the final read — so the clamp hides the one case that would expose a wrong bound.
The loop consumes exactly what a read reports and refuses anything beyond the declared length instead.
The same trap is worth watching for anywhere a second bound looks like prudence.

**The three questions group 2 was left to answer, answered.** The port hands each chunk to a
**synchronous, non-escaping callback without `@Sendable`**, inside one `async` call: an `AsyncSequence`
would let a consumer iterate after the security-scoped window had closed, and marking the callback
`@Sendable` would forbid the plain local accumulator every consumer of it needs. A file with no audio
yields a **valid, empty spectrogram** — `nil` stays reserved for a frame count that could not be
established, which is a different thing to tell a user. **`SpectrogramGenerating` was not created**:
composing decode → fold → finish is orchestration, and it is reconsidered in group 5 only if that
composition turns out to hold logic that does not belong in the composition root.

**Why this slice matters beyond the drawing:** it executes the reversal condition ADR-0015 wrote for
itself. The first FFT is the second consumer of the decoded stream, so `AudioDecoding` becomes a real
seam and `AudioInspectorAnalysis` gains its first contents — behind a seam that exists, not because a
module was waiting to be filled.

**What the spike settled, with numbers rather than convention:** the current transform API is
`vDSP.DiscreteFourierTransform` and it is **not `Sendable`**, so its setup is confined to one operation
and reused — recreating it per frame costs ten times as much. Channels must be transformed separately
and combined in the **frequency** domain; combining samples was measured to invent spectral content
that exists in no channel, which for an instrument that shows where energy stops could conceal the very
thing it is looking for. Reduction is by **maximum**, because the mean buries a short transient by
almost 9 dB. The final incomplete window is discarded rather than padded.

**What it refuses to do:** say what a cutoff means. The drawing can show that energy stops and that the
edge is abrupt; it cannot separate lossy encoding from the master or from deliberate filtering, and two
measured limits — scalloping loss, and an edge that reads **high by up to about three reduced bands and
never low** — are why. That second figure is group 8's, and it is wider than the spike's prose claimed;
the spike's own table already said as much. Automatic detection of lossy origin is a **separate future
change**, and must carry evidence, alternative explanations and confidence rather than a verdict.

**What group 8 corrected rather than absorbed.** Two containers written from the same specification do
not necessarily hold the same samples: our FLAC fixture is written from a 24-bit source where WAV, AIFF
and ALAC take 16, so its model differs — but only in the **quantisation noise floor** around −110 dBFS,
by 0.0025 dB anywhere a reader can see. The container still changes nothing about the evidence; the
fixture writer changes the audio. Worth remembering before reading any future "identical" claim as a
statement about the analysis.

**Group 12 made it fast, and the reason it was slow is worth carrying.** A manual run watched a
68 MB FLAC take **33 seconds** to draw. The cost was never the transform, the decode or the allocations:
it was **scalar Swift loops** — the per-bin magnitude, the channel maximum, the band fold and the
per-sample finiteness check — which an unoptimised build runs at roughly 135 ns an iteration whatever
they contain. Moved into Accelerate and the standard library's SIMD, the same file now draws in about
**two seconds from a development build** and **under one from an optimised one**. The drawing itself
stopped being a per-cell fill and became a single image, so a resize costs nothing. Nothing about the
analysis changed: same resolution, same window, same hop, same channel handling, same absolute scale —
and the model is measurably the same, moving at most a hundred-thousandth of a decibel where a fused
multiply-add rounds once instead of twice, with no cell crossing any threshold.

The same group replaced the colour ramp, which is a separate finding and not a consequence of the speed
work. The first ramp was measured sound on luminance and **weak on hue**: four of eight sampled levels
sat in the cyan-teal family, so two levels 45 dB apart could read as similar colours. The ramp adopted
runs near-black → indigo → blue → teal → green → yellow-green → near-white, keeps the same share of the
luminance range where music sits, and stays strictly monotonic. **Colour still says nothing about good
or bad** — it is a quantity, and the manual greyscale check in group 10 now applies to a ramp nobody has
looked at yet.

**Group 9 ran its stop rule and stopped.** The waveform is **not** migrated onto the shared seam, and
the decision was reached by audit before a line of production code was written. Three things block it,
and none is a matter of effort: two decoding faults — a stream that cannot exist, and a chunk that is
not a possible run of audio — have **no honest counterpart** in the waveform's error space, and giving
them one would change that space, which the group forbids itself; a file with a non-positive sample
rate, which the waveform never looks at today, would newly **fail** where it currently succeeds; and
three existing tests drive a format check that loses its only caller through the seam, so they could
neither pass untouched nor be kept honestly. Cost was measured and is **not** the obstacle — an owned
per-chunk copy costs about a quarter more on the read, bounded and acceptable.

**So the two PCM reads stay, as declared debt rather than as an oversight.** That was named as an
accepted cost when the seam was designed, and the property the migration was meant to preserve — two
**separate operations with separate cancellation**, neither able to fail or cancel the other — is
already true and already proved in both directions. Removing the duplicated *implementation* is worth
doing; merging the *operations* never was.

**The spectrogram is functionally finished, and its manual validation is deliberately not.** The
implementation and the optimisation are both complete and the surface works in the real application.
Group 10 — the literal accessibility and by-eye battery — was **deferred by product decision** with the
fixtures and the runbook already prepared. A basic functional check was satisfactory; that is an
impression, not evidence, and none of 10.1–10.6 is recorded as passed. What was and was not observed is
written down in `docs/manual-validation-mvp.md` so a later reader cannot mistake one for the other.

**The debt this leaves is explicit, and it is a validation debt rather than a product one.** Nothing on
the surface is known to be wrong; nothing about it has been certified either. The greyscale reading of
the new ramp, the high-sample-rate files, the adverse states and the accessibility tree are all still
unobserved.

**Carried forward, unchanged:** the waveform's accessibility debt (text sizes not evaluable on macOS as
written; the VoiceOver traversal failed and is parked for a dedicated change) keeps **ADR-0015 at
`Proposed`**. **ADR-0016 is also `Proposed`**: its format matrix has now passed, but its second
condition — the manual validation of the resulting surface — has not been done, and partial evidence
does not promote it. Deferring that validation does not weaken the condition; it postpones the
promotion. The waveform's migration onto the shared seam is planned as the **last, conditional** group
of this slice, with an explicit stop rule that permits deferring it honestly.

**Next step:** decide where the deferred battery lives. It is the only thing between this slice and
closure, and it need not block the next piece of work — moving group 10 into a validation change of its
own would let this one finish while keeping the debt named and owned. The waveform's migration belongs
to a change of its own too, scoped to reconciling the two error spaces first, and nothing about it is
started.

**Update (2026-08-08): part of that deferred battery was actually run.** A person confirmed 10.3
(light/dark contrast) by real observation. **10.4 (the colour ramp's greyscale monotonicity) was also run,
and it failed**: the intensity stops reading clearly enough in greyscale, a real product observation
distinct from the automated luminance-monotonicity test, which still passes. ADR-0016 stays `Proposed`;
this is a real, named defect now, not just missing observation, and fixing the ramp is a separate piece of
work from this session.

**A second thread is open: the design of a two-file technical comparison.** Contract only — no domain,
no surface, no code. It answers exactly one question, *which observable technical facts are the same,
different, or not comparable between these two files*, and refuses the four it cannot answer honestly:
same recording, derived from, more quality, which to keep.

**The decision it exists to force** is that comparing two files is comparing two `Property` values, not
two numbers. An available bit depth against a format that cannot express one is **not** a difference —
nothing was compared, and calling it one manufactures a fact out of an absence. So the comparison is
three-way, *not comparable* is first-class and explains which state each side was in, and no type in it
can express an order, a winner or a score. Signal comparison, hashes, alignment and export are all
deferred by decision, each with its reason written down.

**The domain now holds all of it and nothing more**: the state of one side, the gap, the three-way
comparison of a single property, and the comparison of two whole reports across the eight technical
facts. Pure value types with no imports at all. There is **no flow and no surface** — choosing a second
file is the next piece, and none of it is started.

Two things are worth carrying. The generic constraint sits on the *operation*, not the type: storing a
value needs nothing, and equality is required only where the same-or-different decision is made. That is
also why duration needed no special case — a `Double` falls through the same rule as every other field,
so there is nowhere for a tolerance to live even if someone wanted one.

And the gap's invariant stopped being a check. It was a failable initialiser, which forced the rule's own
caller — having already proved the pair impossible — through an unchecked back door whose safety rested
on the order of two switch branches. Splitting the five states into *available* and the four that are
not, and giving the gap three cases that each name a non-available side, means the contradictory pair has
**no spelling at all**. Every existing test passed untouched across that change, which is the result
worth having.

`FileComparison` is derived, never assembled: declaring its two-report initialiser suppresses the
memberwise one, so a comparison that contradicts its own reports cannot be written. It keeps both reports
whole, because everything it deliberately does not judge — extension, size, warnings, status — is context
a reader still wants, and one copy cannot drift from another.

**The second-file flow now exists too, and it was the risky part.** The flow held one operation number,
so every new selection cancelled the last and dropped whatever was still in flight; a comparison needs a
second inspection that does *not* supersede the first. It now has its own task and its own number,
disjoint from the primary one — a waveform still being produced for the file on screen still lands while
a whole comparison begins and settles. The relationship runs one way only: a comparison never touches the
report, and a new primary inspection ends the comparison, because its left-hand side is being replaced.

The comparison is built the moment the second **report** exists, before that file's visualisations. Those
are still produced, and discarded: expressing *"not asked for"* would need a new case in two outcome
types that three slices depend on, to save work that is already off the critical path — and the visual
comparison slice will want exactly those models. That is written down with its reversal criterion rather
than left as an omission.

**And it is now visible.** *Compare with another file…* sits beside the existing way to pick one; the
comparison appears inside the report, after that file's own properties, and renders nothing at all when
none is asked for. Eight technical facts, both files' values, and what comparing them established **in
words** — same, different, or a sentence naming what each side actually was.

Two choices carry most of the honesty. Both sides go through the report's **own** formatter, so a value
reads identically in a comparison and in a report — and the numbers stay on screen when nothing could be
compared: two uncertain estimates show both figures, both labelled unreliable, while the surface declines
to call them the same or different. And extension, size, status and warnings appear per file with **no
outcome column at all**, so none can appear; the reason they are unjudged is stated rather than left as
an omission.

There is **no score, no count, no winner and no direction** anywhere — not *higher*, not *improved*. The
section says in its own words that it does not establish which file is better, or whether the two hold
the same recording.

The spectrogram stays functionally finished with its manual battery still deferred, and no ADR is
promoted — ADR-0017 included, which waits on the comparison existing against production code and on a
person looking at the surface. **The export's byte-identity under a comparison is now pinned**: the
exporter's own signature takes only an `InspectionReport`, and six tests confirm the *flow* honours that
— a comparison, however it settles, changes not one byte of the first file's JSON and introduces no
comparison-shaped key.

**6.12 is now closed, as an audit rather than a test.** Its `Comparable` half was already a genuine,
passing runtime check; its *no preferred side* half was always going to stay an audit, since Swift
offers no reflection over a type's methods or computed properties. What changed is that the audit itself
was finally performed rather than deferred: the complete public surface of `PropertyComparison`,
`ComparisonGap`, `FileComparison`, `ComparisonRowDisplay`, `ComparisonFormatter` and `ComparisonView` was
read end to end, and none of it exposes anything that prefers one side. The task's own condition —
"until group 3 shows whether there is anything better to do" — has been checked, not assumed: there
isn't, and there cannot be in Swift as it stands. **The test matrix is now closed except for what group 7
observes.**

**Group 7 was attempted twice and is blocked both times, not skipped.** Four real fixtures were built and
the actual app (`App/AudioInspector.xcodeproj`) was compiled and launched to run the
SAME/DIFFERENT/INCOMPARABLE/failed/replace/close pass by hand. The first attempt found two macOS
permissions missing for the process hosting the session — Screen Recording and Accessibility — and
neither appeared after being granted once and the host restarted. Before repeating the whole pass, a
second, minimal check (one `screencapture`, one `osascript` call) confirmed the block persists, and
surfaced a more specific cause on the scripting side: **Automation** — the process is not authorised to
direct `System Events` to inspect or control another app (error -1743) — which sits alongside Screen
Recording as a second, separate gap, distinct from the general Accessibility toggle the first attempt
named.

**This is recorded as ordinary unfinished work, not as `NOT EVALUABLE`.** That label, in this document's
own convention, is for a criterion with no referent on this platform, or a real, repeated interaction
that still fails under ordinary permissions — neither is true here. A person, or a session holding the
permissions any Mac user grants an app once, could finish 7.1–7.4 in minutes; nothing about the platform
prevents it. So none of the four is downgraded to "unobservable," and none is closed by the structural
audit and exhaustive wording scan already on record — consistent with this project's own precedent, the
near-identical spectrogram tasks 10.2 and 10.6 stayed open against comparable automated coverage on the
same ground: a test is not an observation. **7.1–7.4 stay open, unchanged, as real remaining work.**
ADR-0017 stays `Proposed` — its Status line requires "a person looking at it" and states plainly that
partial evidence does not promote it.

**Group 8's mechanical gates (8.1–8.3) do not depend on any of this and could run today**; 8.4 does,
because deciding ADR-0017's status and archiving both wait on the same unmet criterion. So **the change
is not ready to close**, independent of whether the four gates would currently pass.

**Group 8's mechanical gates (8.1–8.3) are done and green**; 8.4 stays open, unchanged, for the same
reason it always was.

**Group 7 is now concluded as deferred, not resolved and not re-attempted further.** A third,
single-purpose permission check gave the same result as the first two, and the block is treated as
settled rather than something to keep polling. **The comparison itself is finished and clean: production
code, closed architecture, complete automated matrix, zero observed defects — in three separate attempts,
none of which got far enough to observe the running app at all.** What is missing is a person actually
looking at the rendered surface, and that has not happened. This is recorded exactly as this project
already records `add-static-spectrogram-visualization`'s own group 10: deferred by decision, nothing
marked, the debt named in `docs/manual-validation-mvp.md` and in `tasks.md` rather than hidden or
reworded away. **Nothing in the ADR, the tasks or this file has been changed to make that debt look
smaller than it is.**

Per that same precedent, a deferred validation does not promote the ADR it gates and does not close the
task that bundles "decide the ADR's status and archive": ADR-0016 stays `Proposed` there for the
identical reason, and its own 11.5 stays unchecked exactly as 8.4 stays unchecked here. **ADR-0017 stays
`Proposed`.** No merge, no push, no `openspec archive` — the change's own 8.4 requires the ADR decision
this debt prevents, and archiving a change with an open, load-bearing task ahead of it is not something
this repository's own convention does.

**A person then ran the comparison for real (2026-08-08), and part of the deferred debt closes on that
evidence.** Three scenarios against the real app with the prepared fixtures — the same FLAC against
itself, two distinct FLACs, and a second file that is not really audio — plus the replace/close flow, all
behaved exactly as specified: no invented difference, no invented failure state, no forbidden word, the
first report never disturbed, the surface's own denial that it ranks the files still present. **This
closes 7.2 and 7.4** on real observation, not on the structural/automated evidence that stood in for them
before.

**The same person returned for a second pass and closed 7.3.** Light and dark were checked against the
comparison surface itself this time, and reported legible in both, with a correct continuous resize. That
leaves exactly **one** open criterion under group 7, not two.

**7.1 was attempted, not skipped, and stays open on this project's own precedent.** VoiceOver reproduced
the report surface's own known, pre-existing traversal gap — focus trapped on *Export JSON*, never
entering the report's content, so never reaching a comparison row either. There is no evidence this
feature introduces a new regression, because the trap sits entirely upstream of where this feature could
be exercised at all — but there is equally no evidence the row-announcement contract is met, since
nothing about it was actually observed. **The identical gap already keeps ADR-0015 `Proposed`, treated as
open debt rather than as an exception**, and the same standard applies here rather than a more lenient
one invented for this change. **One open criterion out of four is still partial evidence** by ADR-0017's
own words ("partial evidence does not promote it"), so **ADR-0017 stays `Proposed`**, unmodified, and 8.4
stays open for exactly that one remaining reason.

**Nothing here changed a line of implementation, an ADR, a spec, or a task's own normative text.** Only
checkboxes and evidence notes moved, and only where the evidence honestly supports them.

**Next step, whenever someone chooses to take it:** 7.1 needs either the pre-existing VoiceOver traversal
gap fixed (a dedicated accessibility change, already named as such for the report surface) or Accessibility
Inspector access from a session that isn't blocked by Screen Recording/Automation, to inspect the
comparison rows' structure directly instead of through VoiceOver's broken traversal. No merge, no push, no
`openspec archive` follows from this session: this change sits one specific, already-known, already-named
accessibility gap away from closing 8.4.

**A third thread is open: an audit of the technical-property model, `add-computed-technical-properties`.**
Contract only — no domain, no port, no code; `Sources/` and `Tests/` are untouched. It answers two
questions with evidence read from the actual property reader rather than assumed: whether a real average
bitrate can be computed from data already in the domain (yes — `sizeBytes × 8 ÷ duration`, always
`uncertain`, never `available`, consistent with what ADR-0012 had already decided about that exact
computation), and which further technical properties are objective facts worth exposing versus
interpretation dressed up as one. Two are rejected by name rather than silently: a "lowest observed
frequency" with no product need on record anywhere in this project, and a generic "dynamic range" field,
which ADR-0006 already forbids as a single truth. Three are named and deferred with their reasons rather
than dropped: true peak (ADR-0006 already governs its methodology), a noise-floor-relative significant
max frequency (needs its own methodology decisions, not a simple reduction — reuses the existing
`Spectrogram` model with no new file read, once designed), and crest factor (free once peak+RMS exist,
but held back so it is not read in isolation as an out-of-context dynamics signal). **ADR-0018** fixes
the one permanent decision this forces: `TechnicalProperties`'s own "no DSP" line means a sample-level
metric can never join it, so it becomes a new peer value type, `SignalLevelMetrics`, beside the report —
exactly the shape `WaveformEnvelope`/`Spectrogram` already use — while a metadata-only calculation like
the new bitrate stays inside the existing type. ADR-0018 is `Proposed`.

**A second pass then audited the first draft itself, before anything was committed, and corrected it in
three places rather than rubber-stamping it.** The bitrate field is named `averageFileBitrate`, not the
first draft's `calculatedAverageBitrate`: the draft had understated how common embedded cover art is and
how much it can inflate the figure (a 3 MB cover on a 3-minute track alone adds roughly 130 kbps), so the
name now keeps *File* directly beside *Bitrate* rather than trusting a doc comment to carry that caveat.
Two naming questions the first draft left open are now closed with a quantified cost instead of deferred:
`declaredBitrate` is kept exactly as it is (it has a real producer, ADR-0012 already treats it as a
permanent tier, and removing a shipped wire field is a bigger change than keeping an honestly empty one);
`estimatedBitrate` is **not** renamed to `frameworkEstimatedBitrate` — breaking an already-shipped
`schemaVersion` 1 key for a cosmetic gain the new field's own name delivers anyway fails its own cost
test outright. And the level-metrics read strategy is now a decision, not an open question: a **third
independent operation over the existing, shared `AudioDecoding` port** — the same one the spectrogram
uses — never coupled to the waveform's own generator, which stays deliberately un-migrated onto that seam
for its own separate, already-declared reasons; coupling a new consumer to that debt would make its
eventual migration harder, not easier.

Nothing is implemented; the next step is picking up group 2 of its tasks (`averageFileBitrate`, the
smallest and cheapest of everything this audit found).

---
_Last touched: 2026-08-08. Overwrite freely; empty is fine._
