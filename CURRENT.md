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
48 kHz accumulator and now the domain model are all closed. No wiring, no other sample rate.**

`LoudnessMeasurement` holds one `Double` of LUFS and its `LoudnessMethod`, and `LoudnessAccumulator.finish()`
returns it — the type that measured is the only one that can name what it ran, and nothing in App or
Feature spells the identity. No value moved and no tolerance changed; only the return type did.

**The method is two identities and no constants**, which is not the shape the ADR predicted before the
type existed. An `algorithm` identity with the revision embedded (`itu_r_bs1770_5_integrated_v1`) and a
`weighting` identity naming where the coefficients came from (`itu_r_bs1770_5_tables_1_2_48k`). The block
length, the hop and both gate values are *not* fields: they are fixed by the algorithm identity, and
fields would only add states that contradict it and that the type cannot police. The second identity
exists so that the published 48 kHz set and a later derivation are distinguishable on the value itself
rather than inferred from a sample rate the model deliberately does not carry.

**Nothing records conformance, and that is a decision rather than an omission.** A measurement cannot
certify itself: conformance is a claim about a process, and agreement with FFmpeg is test-time evidence
about an implementation, not a property of a file. Mono/stereo is a supported scope, not a grade; 48 kHz
is where the coefficients are published, not a tier. A test asserts the identifiers carry none of that
vocabulary, so a field added later for convenience fails rather than slips through.

Also settled by argument rather than convenience: **no channel count and no sample rate on the model** —
both describe the file, are already reported by the technical properties, and would be a second
description this type could not keep consistent with the first. **No range on the value** either: only
`isFinite`. −70 is a threshold on blocks, not a floor on the result, and a programme above full scale
legitimately reads positive.

ADR-0022 stays `Proposed`. Groups 1–5 are closed; 6–9 remain.

**Next step:** the per-rate derivation is task 4.4 and stays a separate thread — the accumulator refuses
those rates until it lands. The nearer work is group 7: one field on `SharedPCMAnalysisOutcome`, one
accumulator in the composition, one line in each of prepare/accumulate/failAll/finish, and no second
read. Group 6's evidence largely exists already at 48 kHz and is deliberately unticked.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-18. Overwrite freely; empty is fine._
