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
**Already integrated, so not threads:** `SignalLevelMetrics` cannot publish a value that is not a
number — every reduction widens to `Double` before it accumulates, the domain model refuses non-finite
values, and an impossible result reaches the existing `failed` outcome rather than a substituted one.
And the flow-state test suites synchronise on a happens-before instead of a `Task.yield()`, which
guarantees nothing: their scripted actions now complete the round trip. Both are merged; the first is
archived.

**Focus: `share-waveform-pcm-read`, group 5 is done — the waveform's isolation is observed, not assumed.**
Every survivor is compared as a **whole outcome** against its own accumulator fed the identical chunks
against the identical stream, which shares no line of the composition. "Not nil" and "is available"
appear nowhere.

- **The waveform failing is its own failure**, and the read outlives it — counted at the port, not
  inferred from a result that looks complete.
- **The other direction is observed too.** True peak is the one sibling with a reachable solo failure,
  so "a sibling fails, the waveform is untouched" is a measured claim rather than an appeal to symmetry.
- **A producer failure is a different thing**, and the interesting case is failing *after* the last
  chunk: coverage is complete, so a plausible envelope exists to be published, and it must not be. That
  test was added because a negative control showed the earlier one could not fail.
- **Cancellation is a third thing**, forced with a two-gate handshake, mid-read and before the first
  chunk. **Absence is a fourth**, and the four empty answers are asserted to differ from one another.

Six negative controls, each reverted in full. **One property is not claimed as observed**: "the waveform
stops receiving once it has failed" has no reachable input, because its only reachable failure arrives at
`finished()`, after the last chunk. The three guards that make the accumulation path unreachable are
asserted instead, as an alarm.

ADR-0021 stays **Proposed** — its criteria still name group 7.

**Next step:** group 6 — the deferral's own tests. 6.1 and 6.2 were already done during group 3, so the
work is to verify that against their literal text rather than to assume it.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-17. Overwrite freely; empty is fine._
