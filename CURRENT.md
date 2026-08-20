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
**No open thread on programme bandwidth.** `add-significant-bandwidth-measurement` is merged
(PR #48, merge commit `f88efe8`) and archived as
`openspec/changes/archive/2026-08-20-add-significant-bandwidth-measurement`. **ADR-0023 is `Accepted`.**

**What `main` now has.** Programme bandwidth — the highest frequency a file carries persistently, within
60 dB of its own programme peak — as a measured fact, end to end: a `SignificantBandwidth` domain value
carrying no verdict, an accumulator whose memory is constant in duration, the sixth consumer of the one
shared PCM read (the read count is still one), its own report section between the integrated loudness and
the spectrogram, and an additive `measurements.programmeBandwidth` key. **`schemaVersion` stays 1.**

**What it refuses to say, by construction.** It is not a cut-off, not an effective sample rate, and not
evidence of upsampling, transcoding, a codec or a quality level. The promoted capability spec carries
that as a requirement of its own — *Draw no conclusion about origin, quality or provenance* — so the
prohibition is now part of the spec rather than only of the surfaces.

**Group 9 was not implemented, and is not pretended to be.** Four follow-ups stay deferred in the
archived tasks: the **shared STFT stage** and **average spectrum** (one piece of work, waiting for the
second consumer that would justify extracting it), **two-file comparison**, and **findings**. The change
archived at 43/47 on this repository's own precedent — `add-true-peak-measurement` archived with five of
its own open — because a deferred item is neither done nor forgotten.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded twelve
snapshots ago is unchanged and still not a thread.

---
_Last touched: 2026-08-20. Overwrite freely; empty is fine._
