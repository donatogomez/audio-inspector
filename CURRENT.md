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
**Focus:** none. `add-waveform-visualization` is implemented, merged and archived, and its specs are
promoted. There is **no functional work outstanding** in that slice: the waveform is drawn inside the
report, read through the native sample seam, and nothing about it is half-built.

**Carried forward — verification, not implementation.** The manual accessibility validation of the
report surface is **not complete**, and it is the reason **ADR-0015 stays `Proposed`**:

- the accessibility **text sizes**, over the waveform and over the whole report, were never exercised
  at the system's largest sizes — macOS offers no system-wide Dynamic Type for a SwiftUI app to adopt,
  so the criterion as written has no referent on this platform and needs rewording or retiring;
- the **VoiceOver traversal** of the report failed: the tree reads correctly under inspection but the
  contents could not be walked. One cause was tested and ruled out; whether the rest is a defect or a
  property of the test environment is not established. It covers the whole report, most of which
  predates the waveform, so it belongs to a dedicated accessibility change rather than to that slice.

**Next step:** undecided. Nothing is in progress, and the next slice is a product choice — the
accessibility change that would take the traversal, or the first real analysis on top of the sample
seam that now exists.

**Open threads, unchanged:** the reduction lives in Media, and what would overturn that is a second
consumer of the same decoded stream — the first level metric or the first FFT makes a chunked-decode
port a real seam. MP3 is verified locally only, never in CI. The drag sources never exercised — iCloud
files, aliases, symlinks, app bundles and Mail file promises — remain open against ADR-0014. The
pinned `en_US` locale still does not follow the user's region, and `Choose another file…` still sits at
the foot of the window while exporting lives in the toolbar.

---
_Last touched: 2026-08-05. Overwrite freely; empty is fine._
