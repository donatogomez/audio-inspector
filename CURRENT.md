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
**Focus:** `add-true-peak-measurement`, groups 1–9 done. **The measurement is now visible *and*
exportable**: `measurements.truePeak`, a sibling of `measurements.signalLevels`, added without a
`schemaVersion` bump.

**Linear on the wire, dBTP only on screen.** The same number reads as `-6.02 dBTP` in the interface and
travels as `0.5` in the document — a test sweeps the bytes to keep it that way. The method travels with
the value, taken from the measurement's own record so a document always describes the methodology that
actually ran, and the filter is an **identity rather than a recipe**: no taps, no window, no
coefficients, and no claim of conformance to a standard whose coefficients this project does not use.

**The distinctions the domain refuses to lose survive the wire.** A silent file that was measured
exports a real `0`; a file with no frames exports an explicit `null` with `sampleCount: 0` beside it,
and the key is present in both cases. A value above full scale is exported unclamped, because that is
the fact the measurement exists to reveal.

**Nothing else moved.** A report without a true peak is byte-identical to before; `measurements` is
still omitted entirely when neither measurement exists; both children are independently optional, so
none of the four combinations is faked. The real path is proved end to end — real file, real decode,
real shared read, real export — because this project has already been caught by unit tests passing
while the wiring was broken.

**ADR-0019 stays `Proposed`.** Export does not promote it: its criteria are agreement with the oracle
demonstrated **against production code** and a manual validation on a file whose true peak genuinely
exceeds its sample peak. Neither has happened.

**Next step:** group 10 — the gates, the manual validation on a confirmed-fresh instance, and the
decision on ADR-0019's status from what was actually implemented. The spike package is deleted there,
per its own rule, once this slice's tests cover what it observed.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
