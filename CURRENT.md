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
**Open thread: `add-two-file-measurement-comparison` — design only, nothing implemented.** ADR-0024 is
`Proposed`, the change validates at 0/35, and no production file was touched.

**The problem.** The A/B comparison compares what the header declares. Everything measured from the
samples — signal levels, true peak, loudness, programme bandwidth — is computed for the second file by
the same shared read and then **discarded**, in two places the code names deliberately. ADR-0017 §9
deferred this because *"none of the metrics it would compare exist yet"*; all four now do, so the compute
cost of the feature is **zero** and what it adds is retention.

**The decisions worth knowing before implementing.** They come from the units, not from taste:

- **Programme bandwidth is never compared by equality of hertz.** Each reading names a cell
  `[f − r/2, f + r/2]`, and two readings are *indistinguishable at their own resolutions* exactly when
  `|f₁ − f₂| < (r₁ + r₂)/2`. That is a statement about the instrument's grid, **not** an uncertainty
  interval — ADR-0023 refuses to publish one and this does not either.
- **Only integrated loudness carries a difference**, in LU, because it is the only metric whose stored
  quantity is already logarithmic and whose difference is a named unit. True peak and signal levels store
  **linear** amplitudes, so their difference would be a *ratio* — which ADR-0017 §3 excludes by name.
- **Loudness compares across the two weightings; true peak does not compare across oversampling
  factors.** The first is licensed by a passing rate-invariance test, the second by nothing — so it is
  written as an explicit pair allow-list, and a third weighting is incomparable until someone measures it.
- **Channels by index only.** Differing counts compare the overall figures and report the mismatch,
  rather than silently asserting that index 0 means the same thing in both files.

**The boundary this feature defends.** It compares measurements. It does not say whether two files hold
the same master, whether one is a remaster, transcode, upsample or lossy source, which has more dynamics,
or which is better. Those are Findings' work; this is a **producer of facts for it**.

**Inherited, and not to be claimed as fixed**: `add-two-file-technical-comparison` is still open at 52/58
and **ADR-0017 is still `Proposed`**, blocked on the VoiceOver traversal gap shared with ADR-0015. This
change extends that surface and inherits that gap.

**Next step: group 1** — confirm the discard against production code and pin the two comparability
gates, before any comparator exists.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision). Programme bandwidth is done, merged and archived; ADR-0023
`Accepted`.

---
_Last touched: 2026-08-20. Overwrite freely; empty is fine._
