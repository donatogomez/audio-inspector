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
**Focus:** `add-shared-pcm-read`, groups 1–2 done. **The spectrogram and the signal level metrics now
come from one read of the file**, where they each decoded it separately before.

> **This branch carries only the shared-PCM thread.** `add-true-peak-measurement` is a separate, active
> thread on its own branch: its change, **ADR-0019**, `TruePeakMeasurement`, `TruePeakAccumulator` and
> their tests are **not here**, so `openspec list` and `docs/adr/` on this branch will not show them,
> and the ADR index has a gap where 0019 will land. That is the separation working, not something
> missing.

**What changed, and what deliberately did not.** One production file — a concrete composition in the app
layer — plus one call in the coordinator that now makes a single decoder where it made two.
`AudioDecoding` and `PCMChunk` are byte-identical, no accumulator moved, no protocol was introduced for
two known consumers, nothing runs concurrently, nothing buffers PCM, and the waveform keeps its own read.
The report is still emitted before any sample, and the same two updates arrive in the same order, so
presentation, flow state and export cannot tell the read is shared.

**The isolation is the point, and it is held by construction rather than by separate decoders.** Each
analysis keeps its own accumulator and its own recorded fault; a faulted consumer stops being fed while
the read continues for the others; the read ends only when *nobody* needs it, never when someone is
done. A decoder failure is treated as a different thing from a consumer failure — every unfinished
analysis ends, but each reports its own outcome, so a reader of one never has to consult another.

**One asymmetry worth knowing before writing more tests.** Only the spectrogram has a failure mode a
valid stream can trigger; `SignalLevelMetricsAccumulator` refuses nothing that `PCMStreamDescription`
allows. The mirror isolation case therefore has no input today, and that is recorded as a test that
starts failing the day it gains one — rather than as a comment nobody re-reads.

**Measured against production code, ten minutes of stereo:** FLAC 1.907 s → 1.471 s and AAC 2.180 s →
1.660 s in Release; WAV, whose decode was nearly free, 0.698 s → 0.656 s. In Debug the saving is larger
still. That is essentially one whole redundant decode removed, which is what the spike predicted.

**Next step:** group 3 — proving the isolation rather than assuming it, including the tests that already
had to be rewritten from asserting the *arrangement* (two decoder instances) to asserting the
*property*. Group 4 then re-measures the saving in the spike's own form.

**ADR-0020 stays `Proposed`**: its promotion needs the saving reproduced against production code *and*
every isolation property demonstrated by a test that fails when the property is broken — group 3's job.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
