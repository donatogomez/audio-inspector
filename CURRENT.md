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
**Focus:** `add-true-peak-measurement`, groups 1–8 done. **True peak and the clipped-sample count are
now demonstrated to be independent measurements**, not one measurement and its consequence.

**What the demonstration rests on.** They observe different things: the clipped count looks at stored
samples at or beyond full scale, the true peak at the waveform reconstructed *between* them, where
seven of every eight points examined are values no array position holds. The case that proves it is a
tone whose every stored sample sits at 0.85 while the waveform reaches 1.2 — **zero clipped samples and
a true peak above full scale, both truthful at once**. A file with both, and a file with neither, are
tested beside it, and measured silence is kept apart from a file with no frames because collapsing them
would lose the distinction both domain types exist to preserve.

**Non-derivation is proved by consequence**, since Swift cannot be asked to show a type lacks a member:
each result equals what its own accumulator produces from the same audio with the other never
constructed. A search backs it — every mention of one metric inside the other's files is a comment, and
no code path, warning or comparison joins them.

**No diagnosis anywhere.** A positive true peak is a value, never a flag. That implements **ADR-0019**,
which narrows ADR-0006's "flagged when true peak > 0" sentence rather than contradicting it: a flag is
an inference and belongs to `findings`, with evidence and confidence attached — and `findings` does not
exist yet.

**Deliberately not done.** No export: the value stops at the flow state and the screen, and the JSON
contract, the DTO and the exporter are untouched.

**ADR-0019 stays `Proposed`.** Its criteria are agreement with the oracle demonstrated **against
production code** and a manual validation on a file whose true peak genuinely exceeds its sample peak.
Neither has happened; the surface that validation needs now exists.

**Next step:** group 9 — export. `measurements.truePeak` beside `measurements.signalLevels`, its null
rules, its unit, the isolation `signalLevels` already proves for a report without one, and the schema
document updated in the same form.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
