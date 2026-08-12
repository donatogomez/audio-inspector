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
**Focus:** `add-shared-pcm-read` is **finished and published, waiting on review and merge.** The
spectrogram and the signal level metrics are produced from **one** PCM read instead of two; the
waveform keeps its own, so an inspection reads the file twice rather than three times.

> **This line of work carries only the shared-PCM thread.** `add-true-peak-measurement` is a separate,
> active thread on its own branch: its change, **ADR-0019**, `TruePeakMeasurement`, `TruePeakAccumulator`
> and their tests are **not here**, so `openspec list` and `docs/adr/` will not show them, and the ADR
> index has a gap where 0019 will land. **It stays blocked until shared PCM reaches `main`**, and then
> resumes by wiring true peak as a third consumer of the shared read — not by redesigning anything it
> already finished.

**What holds this up, in one line each.** Independence is now a property of the composition rather than
of separate decoders, and it is proved by tests that fail when it breaks — a consumer's failure, a
producer's failure, and a cancellation forced deterministically while the read is provably mid-flight.
The saving was re-measured against production code, not against the spike's harness, and one decode's
worth of time disappears in every format and both build configurations. A person then looked at the
real app on a confirmed-fresh instance, over a real uncompressed and a real compressed file, and found
the surface unchanged.

**ADR-0020 is `Accepted`.** Its own promotion criteria were met and were not softened to fit; its
`Promotion` section also records where the evidence is weaker than promised — the "no consumer starves
another" rule has no reachable input today, so it stays contract text rather than a test.

**Two things deliberately left undone, so they are not mistaken for oversights.** The waveform still
reads the file for itself: migrating it is its own change and would take two reads to one.
`SpectrogramGeneration` and `SignalLevelMetricsGeneration` are no longer wired into an inspection but
are **kept**, because they are the independent implementation the equivalence tests compare the shared
read against; deleting them is a separate decision, not a tidy-up at the end of this one.

**Next step:** review, then merge. **`openspec archive` runs only after the merge** — that is the one
part of the task list still open, and it stays open on purpose. One cosmetic defect was seen during
validation and left alone: on a 64 kHz file the spectrogram's frequency axis draws its Nyquist label
over the next tick. It lives in presentation, predates this change, and fixing it here would widen a
finished diff.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
