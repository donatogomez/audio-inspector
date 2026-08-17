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
**Focus: designing `add-loudness-measurement` — integrated loudness (LUFS-I), investigation done, no
production code written.**

The decisive finding is what the investigation **could not** establish: the normative constants of
BS.1770 / R128 are not in this repo and were not read, so no coefficient, gate value or block length is
recorded anywhere in the design. Building on remembered ones would be unverifiable. What the spike
produced instead is an **acceptance target** measured from FFmpeg's `ebur128` — the K-weighting response
curve, a 1 kHz calibration anchor (stereo −20 dBFS reads −20.0 LUFS, mono reads −23.0), a gating fixture,
and rate-invariance from 44.1 to 192 kHz — plus the oracle to check against. Obtaining the constants is
task 1, not a detail.

- **Mono and stereo only.** Measured: stereo reads exactly 3.01 dB above mono for the same signal, so the
  weighting follows from the channel count. Beyond stereo the standard weights by channel *position* and
  the pipeline has no layout — `PCMStreamDescription` carries none and the property reader deliberately
  never infers it. So other configurations get **no value**, not a guessed one.
- **Integrated alone.** Momentary and short-term are meter readings; putting one in a static report means
  choosing a reduction, and that is a product decision. LRA depends on short-term.
- **The domain stores LUFS**, unlike true peak's linear — here the normative quantity *is* the
  logarithmic one.
- **Affordable**: the fold measures ≈0.14 s on ten minutes of stereo, about half the waveform's, on a
  read that already happens.
- **Left open on purpose**: what digital silence reports. The reference returns −70.0 LUFS for both
  silence and a 300 ms file, which are two different situations; the too-short case is *not computable*,
  and silence needs the standard's definition of the absolute gate before it is answered.

ADR-0022 is `Proposed`. Nothing is implemented.

**Next step:** obtain BS.1770 and R128 and complete task group 1. Everything else waits on it.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-17. Overwrite freely; empty is fine._
