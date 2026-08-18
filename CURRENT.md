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
**Focus: `add-loudness-measurement` — integrated loudness (LUFS-I). Methodology, official targets, the
domain model and now the multi-rate weighting are closed. Nothing is wired yet.**

`LoudnessAccumulator` measures **44.1 / 48 / 88.2 / 96 / 192 kHz**, mono and stereo. The supported set is
enumerated rather than open-ended: each rate is one the derivation was measured at, and an unmeasured one
is refused rather than derived for, because deriving would claim a response nobody checked.

**Two tiers, and the value says which it got.** At 48 kHz the published coefficients run literally — not
through the derivation, whose round-trip is exact in the response (0.000000 dB) but *not* bit-identical
in the coefficients (4.4 × 10⁻¹⁶), and "the published numbers ran" should mean exactly that. Every other
rate carries `itu_r_bs1770_5_48k_prototype_rediscretised_v1`, which names our **method** rather than the
goal, because two constructions could both claim to match a response.

**The derivation was chosen by measurement, not by custom.** Recover the analogue section each published
one is the bilinear transform of, prewarped at *that section's own* natural frequency — derived from the
section, not picked — then re-discretise. Worst response error **0.0077 dB**. The alternatives: no
prewarp 0.0157, one shared frequency 0.0521, a numerical fit 0.00736 — a 4.6 % improvement for two magic
numbers, declined. A prewarp frequency chosen by habit would have been wrong by decibels (8 kHz → 1.2 dB,
16 kHz → 5.7 dB).

The tolerance is **0.02 dB**, fixed after measuring: five times inside the publishers' ±0.1 LUFS, under
FFmpeg's own 0.03 LU drift, and 2.6× over what we produce. Our reading moves **0.0066 LU** across the
five rates — **more rate-invariant than the oracle**, which is why the FFmpeg delta grows with rate
(0.0056 → 0.0426) and why that comparison stays bounded at the published ±0.1 rather than tightened onto
the oracle's own drift.

`Double` coefficients, also measured: `Float` would cost 0.0146 dB at 192 kHz, three quarters of the
budget. Building them is ~0.5 µs per file. The fold scales with the rate because there are more samples,
not because the derivation costs anything per sample — though 48 kHz did go 0.243 → ~0.27 s (+11 %) when
the coefficients stopped being compile-time constants, and special-casing it back was declined.

Chunk independence is still **bit-exact, at every rate**.

ADR-0022 stays `Proposed`. Groups 1–5 closed, 6 all but its oracle/negative-control items.

**Next step:** group 7 — the fifth consumer of the shared PCM read: one field on
`SharedPCMAnalysisOutcome`, one accumulator in the composition, one line in each of
`prepare`/`accumulate`/`failAll`/`finish`, no second read and no new abstraction.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-18. Overwrite freely; empty is fine._
