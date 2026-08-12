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
**Focus:** `add-true-peak-measurement`, groups 1–7 done. **The measurement is on screen**, in its own
section beneath *Signal levels*, quoted in **dBTP** and produced from the shared PCM read rather than
from a fourth decode.

**What the surface says, and what it refuses to say.** A true peak above full scale reads `+0.83 dBTP`
— signed, unclamped, uncoloured, unflagged. There is no warning, no badge, no comparison against the
sample peak and none of the vocabulary that turns a number into a diagnosis; a sweep over every string
the section can produce pins that, aimed at the value most likely to attract one. Absence stays
distinct from a measured zero: a channel that carried no samples has no maximum, while a silent one has
a real value that floors like every other level in the report.

**The method travels with the value**, in words, taken from the measurement's own recorded factor and
filter rather than from constants repeated in the surface — so a file measured under a different method
could not be described under this one. **No standard is claimed anywhere**, because this filter was
designed to recorded parameters and validated against analytic truth and an independent meter, not
built from BS.1770 Annex 2's own coefficients.

**Deliberately not done.** No export: the value stops at the flow state and the screen, and the JSON
contract, the DTO and the exporter are untouched. `TruePeakMeasurement` and `TruePeakAccumulator` are
unchanged.

**ADR-0019 stays `Proposed`,** and presentation does not promote it either. Its criteria are agreement
with the oracle demonstrated **against production code** and a manual validation on a file whose true
peak genuinely exceeds its sample peak — the surface that validation needs now exists, but the
validation itself has not happened.

**Next step:** group 8 — proving that true peak and the clipped-sample count are independent: a file
with zero clipped samples and a true peak above full scale, a file with both, and a quiet file with
neither, plus a search and a test that no code path derives one from the other.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
