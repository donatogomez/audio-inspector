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
**Focus:** `add-true-peak-measurement` is **finished and ready to publish.** True peak exists end to
end: measured from the shared PCM read with **no decode of its own**, shown in **dBTP** with its method
stated in words, exported **linearly** under `measurements.truePeak`, and demonstrated to be
independent of the clipped-sample count.

**ADR-0019 is `Accepted`**, promoted on its own two conditions and nothing else. The oracle agreement
was demonstrated against the **production path** — a gate that drives the real decoder and the shared
read rather than the accumulator in isolation — at **0.0005 dB** against FFmpeg where the pinned
tolerance is 0.05 dB. And a person saw the surface: on an analytic fixture whose waveform crosses full
scale *between* samples, *Peak sample* −1.43 dBFS, *Clipped samples* 0 and *True peak* +1.58 dBTP were
read together, with no warning, colour or diagnosis attached. Its `Promotion` section records what the
evidence does **not** cover — the 192 kHz exclusion, the smooth-boundary signal class, the standing
refusal to claim BS.1770 conformance, and the finding that is still not authorised.

**The spike package is deleted**, its own criterion met; the durable report stays in `docs/spikes/`.

**What this change deliberately does not contain**: no LUFS, no loudness range, no crest factor, no
significant maximum frequency, no `findings`, no inter-sample-clipping flag, no score, no new decoder
and no external dependency. A positive true peak is a value, and turning it into a verdict needs a
structure that does not exist yet.

**One thing is inherited rather than fixed**: interactive VoiceOver still does not enter the report's
contents — a gap this document's runbook has recorded since the waveform slice. True peak adds a section
to that same area, so it neither worsens nor repairs it, and nothing here claims a VoiceOver pass.

**Next step:** publish — push the branch and open the PR, then merge. **`openspec archive` runs only
after the merge**; that is the one part of the task list still open, and it stays open on purpose.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
