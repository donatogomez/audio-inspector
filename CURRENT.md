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
**Open thread: `add-significant-bandwidth-measurement`.** Groups 1-7 are complete. The DSP is built,
wired as the sixth consumer of the one shared PCM read, validated against production, and now **on
screen**: its own section between Integrated loudness and the spectrogram, showing one value, the
resolution it sits on, and one sentence about how it was measured. No export yet, no comparison, no
findings.

**Presentation settled three things that were easy to get wrong**, and each is a refusal rather than a
feature. The visible name is *Programme bandwidth* — not "effective sample rate", which would claim the
file should have been stored differently, and not "cut-off", which asserts a filter nobody observed. The
resolution is a **second row, never a `±`**: it is a bin width, not an uncertainty, and the reading is
already biased upward by leakage, so a symmetric interval would be wrong in kind and in shape. And the
displayed precision is derived from the resolution, so no digit claims a distinction the bins cannot
make — one decimal in kilohertz at all five rates, which falls out of the window being fixed in time.

**Nothing on the surface judges.** No colour, badge or weight varies with the value; a reading at the top
of the band renders exactly like one in the middle; nothing compares it to Nyquist or to the declared
rate; and there is deliberately no disclaimer sentence, because "not an upsampling diagnosis" would
introduce the frame the measurement refuses and be longer than the fact it qualifies.

**What group 7 could not do, and did not pretend to.** The surface is pinned by tests down to the exact
rendered strings, but `swift test` cannot tell whether the section *reads* as a fact to a person seeing
it in place. That is ADR-0023's third promotion condition and it is still open. The runbook is written
and the fixtures exist with their expected displays computed **before** the app is opened — five files
under `/tmp/programme-bandwidth-manual`, recorded in `docs/manual-validation-mvp.md` as PREPARED, not
executed. Fixture 4 is the one that matters: a 16 kHz programme with one click in it, which must be
indistinguishable from the same programme without it.

**Next step: group 8, the export** — additive under `measurements`, `schemaVersion` stays 1, the key
omitted when absent, carrying the frequency, the resolution and the method identity, and no verdict.
Then group 10's gates and the manual pass that promotes ADR-0023. The record stays `Proposed` with two
of three conditions met.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded nine
snapshots ago is unchanged and still not a thread.

---
_Last touched: 2026-08-20. Overwrite freely; empty is fine._
