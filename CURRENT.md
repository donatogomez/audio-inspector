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

**Focus: `share-waveform-pcm-read`, group 7 is done and ADR-0021 is `Accepted`.** An inspection reads a
file's samples once, measured end to end against a clean `main` worktree — ten minutes of stereo,
Release, three runs, medians:

| format | before | after | saving |
| --- | --- | --- | --- |
| WAV | 1.243 s | 1.198 s | 0.045 s (3.7 %) |
| FLAC | 2.465 s | 1.788 s | **0.677 s (27.5 %)** |
| AAC | 2.324 s | 1.964 s | **0.359 s (15.5 %)** |

- **The task's own success rule was the wrong comparison.** "Saving ≈ the eliminated decode" would have
  raised a false alarm on AAC at 68 %. What is removed is a whole legacy *read* — decode and fold —
  while a fold is added back inside the shared pass; against that the arithmetic closes at 128/101/97 %.
- **No hidden cost**: the waveform's fold is 0.297–0.309 s, unchanged. Memory is flat — a tenfold longer
  file moved the peak footprint by 0.2 MB.
- **The waveform is visible 0.8–1.3 s later than it used to be**, because it settles with the one read
  instead of after a read of its own. No spec requires it earlier and the report still precedes the read
  by three orders of magnitude, so nothing is broken — but it is a real change in what a user sees, it
  was not predicted, and it is written into ADR-0021's Promotion section. Progressive delivery inside the
  shared pass is the obvious remedy and is deliberately **not** designed: it would reopen a callback
  contract ADR-0020 closed, and that is a product decision, not a reflex.
- **A negative control found a hole**: nothing was testing that the report precedes the *read* — only its
  order relative to the other updates. A test that asks the decoder whether it had been invoked yet now
  covers it.

**The change is ready to publish.** All six gates are green on the head being proposed, and every group
is closed except the archive, which belongs after the merge. ADR-0021 is `Accepted`, the legacy
generator survives only as a test oracle with a gate against its return, and the waveform's later
arrival is recorded as a known consequence rather than smoothed over.

**Next step:** review the pull request. On merge, `openspec archive share-waveform-pcm-read` and refresh
this snapshot — nothing else is outstanding.

**Minor follow-up, not a thread:** `ImportFlowComparisonTests` has one `Task.yield()` that was never
audited in depth; same shape as the ones above, no failure ever attributed to it.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-17. Overwrite freely; empty is fine._
