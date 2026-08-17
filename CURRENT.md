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
**Focus: `add-loudness-measurement` — integrated loudness (LUFS-I). Methodology closed against the real
standards, and the official targets are now executable. Still no production code.**

**The official vectors exist and pass, before anything computes loudness.** EBU Tech 3341 §2.9 and
Table 1 tests 1–5 plus BS.1770-5's own anchor are transcribed as data with their source attached,
generated natively, and measured. That ordering is the point: a target fixed after the implementation is
a target that was fitted to it. Two numbers came out of it — the oracle reproduces every published
expectation with a **worst deviation of 0.021 LU**, and its **own rate-invariance is 0.03 LU, not zero**,
which bounds any agreement claim across rates.

The battery is split by tool dependence so CI keeps its value: transcription, discrimination and output
parsing run everywhere; only the measurement is gated on FFmpeg. Two guards exist because the oracle
cannot supply them — a mis-transcribed **level** would match its own wrong fixture, and a wrong
**duration** returns −23.0 under several values — so levels are checked against their own readings and
durations are simply stated twice. Both were confirmed by breaking them.

The blocking unknown is gone. BS.1770-5 (11/2023), R 128 v5.0, Tech 3341 v4, Tech 3342 v4 and Report
BS.2217-2 were obtained and read, and every constant now sits in the spike's **Part A** with its document,
revision and section. Part B keeps the FFmpeg measurements separate; nothing is mixed.

The finding that changed the shape of the feature is **not** a constant. **BS.1770-5 publishes filter
coefficients for 48 kHz only** and asks other rates merely to *match that frequency response* — no
prototype, no per-rate table, no transform, no tolerance. So the compliance claim has **two tiers**: exact
at 48 kHz, a demonstrated equivalence everywhere else against a derivation we choose. That is weaker than
what most tools assert, it is what the text supports, and it is now what the measurement's methodology has
to carry so the two never look alike on the page.

- **Mono and stereo only, and now with a proof rather than a caution.** Three channels is the
  counterexample: L/C/R would all weigh 1.0, but the file could carry an **LFE the standard excludes
  entirely**, and getting that wrong moves the result by more than the ±0.1 LUFS the standards tolerate.
- **Silence is settled, and it is an absence.** A silent block's loudness is −∞, so nothing passes the
  absolute gate and the definition divides by zero; BS.2217-2 expects "lowest resolvable value or
  −infinity" and declines to name −70. **−70 is the gate, never a result.** Too-short is an absence for a
  different reason — no block exists at all — and the boundary is exact: 400 ms measures, 399 ms does not.
- **The acceptance targets are published now, not observed.** Tech 3341's tests 1–5 and its §2.9
  calibration are pure tones with published expected values at ±0.1 LUFS; #3 and #4 are the relative- and
  absolute-gate discriminators. The spike's own fixtures are demoted to corroboration.
- **The oracle is qualified**: FFmpeg 8.1.2 passes those same published tests within tolerance. It is
  still absent from CI, so its suite stays local evidence.
- **Exact O(1) memory is impossible**, not merely awkward — the relative gate depends on the whole
  programme. One energy per block, ≈288 kB/hour, and the histogram shortcut is rejected.

ADR-0022 stays `Proposed`: the constants half of its promotion condition is discharged and the targets
are fixed, but nothing implements them. Groups 1 and 5 are closed; 2–4 and 6–8 are untouched.

**Next step:** task group 2 — the `LoudnessAccumulator` in `AudioInspectorAnalysis`, straight from the
pseudocode in design §6, with the 48 kHz coefficients used literally and the per-rate derivation left for
4.4. Group 6 then re-points the existing vectors at production instead of at the oracle, which is a
one-line change per test rather than new evidence.

**Open on purpose, and only these two:** the numeric tolerance for "the same frequency response" away
from 48 kHz, and the oracle comparison tolerance on real files. Both are picked from measurement once an
implementation exists; choosing either now would be picking a number to be right about.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-18. Overwrite freely; empty is fine._
