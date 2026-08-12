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
**Shared PCM is done: merged and archived.** An inspection reads the file **twice**, not three times —
the spectrogram and the signal level metrics are folded from **one** decode, each keeping its own
accumulation, its own failure and its own outcome. The waveform still reads for itself, deliberately:
it uses a different port and its accumulator needs frame position, so migrating it is its own change
and remains the obvious next reduction. `AudioDecoding` and `PCMChunk` were not touched, and the
capability that says a file's samples are read once now lives in the canonical specs.

**ADR-0020 is `Accepted`** — *independent analyses* is the invariant, *independent decodes* was only the
implementation ADR-0016 chose while a decode looked free. Its `Promotion` section carries the evidence
and, honestly, the one place the evidence is thinner than promised.

**True peak is the next thread, and it is no longer blocked.** Its work sits on its own branch: the
model, the accumulator, the methodology and their tests are finished, ADR-0019 is still `Proposed`, and
its groups 1–5 are closed. Only its group 6 remained, and it was waiting for exactly one thing — a
shared read existing in `main` — which now exists. The step is to reconcile that branch with `main` and
then wire true peak as a **third consumer** of the shared read: no fourth decode, and no redesign of an
accumulator or a model that is already finished. If wiring it ever required changing the accumulator,
that is evidence the architecture is wrong and has to be justified before proceeding.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
