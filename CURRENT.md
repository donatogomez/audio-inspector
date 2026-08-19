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
**Open thread: `add-significant-bandwidth-measurement`.** Groups 1 and 2 are complete. There is still no
production code for this change; group 3 is the accumulator and it is now authorised.

**Group 2 asked one question: does the fact survive the transport?** It does. The method left in-memory
arrays and went onto real files through the production decoder — five sample rates, five lossless
containers, AAC, MP3 and rewrap, seven chunk sizes from one frame to the whole file, and every file
edge. Lossless containers and chunk sizes agree on the **identical bin**, asserted exactly rather than
within a tolerance, because the measurement is a pure function of the samples and a tolerance there
would hide a decoder difference instead of revealing one.

**The resolution contract came out of measurement, not out of a choice.** Across four known edges and
five rates the error is always positive — one-sided upward, as the Hann derivation said — and worst-case
4.55 resolutions against the analytic reach of 4.72. So the assertion is `0 ≤ error ≤ 5 × resolution`,
and the raw hertz are explicitly *not* comparable across rates: each rate quantises the edge onto its own
bin grid, and 12 kHz reads +1.00 resolutions at 48 kHz and +4.55 at 44.1 kHz for that reason alone.

**Lossy came out better than expected.** A 64 kbps MP3 reads its own low-pass — 16 790 Hz where the
source reads 20 075 — and a 320 kbps one keeps the source's edge; AAC moves four bins. Codec artefacts
above the low-pass stayed under the threshold, so nothing had to be widened to accommodate a codec, and
every bitrate survives a rewrap to PCM with the identical bin. That last row is evidence about spectral
extent and nothing else: it says two files measure the same, never where either came from.

**FFmpeg is settled, and by measurement.** Its `aspectralstats` `rolloff` under-reads a 16 kHz limit as
15.2 kHz, and adding a dominant 100 Hz tone drags it to 12.5 kHz while the extent does not move. It
tracks spectral balance, not extent. There is no external oracle for this quantity, and now that is a
measured statement rather than an assumed one.

**Two things group 2 hands forward.** An impulse alone in digital silence reads as broadband — not a
persistence failure but eligibility interacting with it, since removing empty windows raises the share
of the few that remain, and a programme has to occupy about a quarter of the file before an isolated
click stops setting the answer. It is pinned by a test. And bounded memory (task 3.3) is harder than it
reads: the budget compares each window against the file's peak, which is not known until the end, so a
plain per-bin counter cannot decide eligibility as it goes. Counters stratified by window peak into dB
buckets are one shape that stays bounded.

Three self-inflicted faults are written into the spike rather than quietly fixed, because each would
pass unnoticed: a hard amplitude step in a fixture is broadband and measured as Nyquist; a comb of 32
components at 0.05 clips and measures its own clipping; and a fast path must associate its arithmetic
exactly as the slow path writes it, because the support tests compare them bit for bit.

**Next step: group 3, the accumulator** — `SignificantBandwidthAccumulator` in `AudioInspectorAnalysis`,
taking `PCMChunk` like its five siblings, with chunk independence demonstrated by a test that fails when
it is broken, bounded memory per 3.3, and the mono/stereo decision (3.4) that group 2 deliberately left
open by measuring each channel separately.

ADR-0023 stays `Proposed`. Its first promotion condition is met; the other two — the impulse control
against production code, and human validation of the surface — cannot be met before the accumulator
exists.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded five
snapshots ago is unchanged and still not a thread: the export chain's third positional optional,
`ReportJSONDTO.swift` at 415 lines against SwiftLint's 400, the absolute gate not being observable from
outside `LoudnessAccumulator`, and the unaudited `Task.yield()` in `ImportFlowComparisonTests`.

---
_Last touched: 2026-08-19. Overwrite freely; empty is fine._
