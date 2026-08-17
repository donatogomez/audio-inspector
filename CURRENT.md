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

**Focus: `share-waveform-pcm-read`, group 6 is done — the legacy seam is retired from production and
kept, deliberately, as a test-only oracle.** Production reads a file's samples once; no target under
`Sources/` names a waveform-reading port; nothing constructs one.

- **The deletion the task asked for would have cost a guarantee.** The equivalence suites compare the
  shared fold against an implementation with its *own* read loop and its own frame accounting. Delete
  it and they still pass — comparing the shared path with itself. Folding against a bare accumulator is
  no substitute: it consumes the same chunks from the same decoder, so it checks the composition and
  never the transport. The task text conflated "retire the production read" with "delete the types";
  it was corrected rather than carried as a false debt, and ADR-0021's decision 4 with it.
- **Moving the oracle out of `Sources/` is architecturally blocked**: `check-boundaries.sh` rule 6
  confines AVFoundation to `AudioInspectorMedia`, so the move needs either a broken boundary or an
  abstraction invented to relocate a test helper.
- **The risk that justified deleting it is answered by a gate instead**, now asserted over every
  production target rather than only the composition root. It found a real offender on its first run.
- **`FakeWaveformGenerating` is gone**, and that one really was dead: its only consumer was its own
  test suite.

ADR-0021 stays **Proposed** — group 7 is still open.

**Next step:** group 7 — confirm the saving against production code, and check memory and delivery order
while there.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-17. Overwrite freely; empty is fine._
