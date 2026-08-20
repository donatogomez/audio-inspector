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

**Open thread: `add-two-file-measurement-comparison` — groups 1 to 6 closed, nothing exported.**
ADR-0024 is `Proposed` and stays there.

**Focus.** The measurement comparison is on screen: a sub-section beneath the technical rows, in the
report's own metric order, with four figures for the levels, one for true peak, one difference in LU on
loudness alone, and two grid-shaped words for bandwidth. Fourteen negative controls were applied and
reverted. Nothing in the export, the JSON schema, Findings or the two visualisations was touched, and
Domain did not need to change at all.

**Next step: the manual validation ADR-0024 is waiting on.** Its third promotion criterion is a person
looking at the surface. The battery is prepared with real production figures and expected strings in
`openspec/changes/add-two-file-measurement-comparison/README.md`, so the check is against numbers that
already exist rather than a judgement made at the window. After that: group 8's gates and closure, and
`openspec archive` **after merge**.

**What that person is checking that a test cannot.** Whether seven rows plus their notes stay legible at
a narrow window; whether the difference column reads as a missing value on the six rows that have none;
and whether anything on screen invites ranking the two files.

**One decision the surface forced, now recorded in ADR-0024 §5.** Honest formatters make two rows look
self-contradictory: two bandwidth readings one bin apart both display as `16.1 kHz` beside `Separated`,
and two DC offsets around 10⁻¹⁴ both display as `0.0000` beside `Different`. The answer is a sentence
saying the display rounds them together — **never another digit**, which would claim precision the
measurement does not have.

**Open question carried forward.** `incomparable(.methodsDiffer)` is a state the surface renders and
**no pair of real files can produce**: production runs one true peak method, one bandwidth identity and
one loudness algorithm with only the two allow-listed weightings. It is validated in the presentation
tests. Adding a public setting so a screenshot could be taken would be a worse answer than the gap, so
the manual battery names the exclusion instead of faking it.

**A limit worth knowing before the surface is judged.** When a measurement is `incomparable`, **neither
column shows a value**, because the domain's gap carries no surviving number — so a file whose sibling
has no loudness shows `No value` on both sides rather than its own figure beside the absence. That
figure is on screen anyway, in the primary file's own report section above. Widening the flow to publish
both bundles alongside the comparison would change that, and it was left out of scope deliberately: it
puts two values and one outcome on the surface from two different places, which is the atomicity risk
group 3 exists to prevent.

**Inherited, and not to be claimed as fixed**: `add-two-file-technical-comparison` is still open at 52/58
and **ADR-0017 is still `Proposed`**, blocked on the VoiceOver traversal gap shared with ADR-0015. This
change extends that surface and inherits that gap.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision).

---
_Last touched: 2026-08-21. Overwrite freely; empty is fine._
