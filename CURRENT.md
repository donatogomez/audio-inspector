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
**Focus:** `add-true-peak-measurement`, groups 1–5 done — and **group 5's stop rule fired, so the
wiring is blocked.** The measurement, its model and its accumulator are finished and tested; nothing in
the app produces a true peak, and nothing should until a separate change lands.

**What the end-to-end measurement found.** Reading the file a **fourth time** — computing nothing on it
— costs about **a quarter of a whole inspection** for FLAC and AAC, which are this product's actual
subject. The design had accepted the fourth read partly on a cited figure of 0.035 s per decode; that
number describes the cheapest uncompressed case, and against the real port a compressed file costs an
order of magnitude more. `design.md` §8 kept an escape hatch for exactly this disagreement, and it is
used rather than argued around: nothing was folded, merged or migrated, and the number is recorded in
`docs/spikes/2026-08-12-true-peak-end-to-end-cost.md`.

**The two costs have different remedies, and only one is the architecture's.** The fourth *decode* is
what a PCM-sharing seam removes — and it would speed up the existing three operations too, since a FLAC
inspection already spends most of its time decoding the same file three times. The true-peak **DSP**
(about half a second for ten minutes of stereo) is the feature's own price and no sharing touches it.

**What the verdict does not overturn**: ADR-0016's independent-operation rule stands. The objection is
to a fourth *read*, not to a fourth *consumer* — one pass feeding several accumulators keeps the
independent cancellation and failure that rule protects. Also confirmed while measuring: the report is
emitted before any sample read (~1 ms), so a later operation cannot delay the report, the waveform, the
spectrogram or the signal level metrics; and the accumulator's memory stays bounded by the chunk, never
by duration.

**Next step:** a **new OpenSpec change for PCM sharing** — one read of the file feeding the existing
consumers, built *on top of* the `AudioDecoding` seam rather than by changing it, exactly as ADR-0016
permits once measurement justifies one. Group 6 of the true-peak change resumes after it, unchanged.

**ADR-0019 stays `Proposed`**, and this verdict does not touch it: it is about what a true peak is and
how it is reported, not about how many times the file is read.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
