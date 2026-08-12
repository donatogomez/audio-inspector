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
**True peak is done: merged and archived.** It exists end to end — a domain value that carries its own
method, an Accelerate accumulator, a **third consumer of the shared PCM read** that costs its DSP and
no extra decode, a *True peak* section quoting **dBTP**, and `measurements.truePeak` on the wire in
**linear** amplitude beside the method that produced it, still under `schemaVersion` 1.

**ADR-0019 is `Accepted`**, promoted on its own two conditions and nothing else: the oracle agreement
demonstrated against the **production path** rather than a spike — 0.0005 dB where the pinned tolerance
is 0.05 dB — and a person reading the surface on a file whose true peak genuinely exceeds its sample
peak. Its `Promotion` section records what that evidence does *not* cover, including the 192 kHz
exclusion and the standing refusal to claim BS.1770 conformance.

**No true-peak thread is open.** A positive value is reported as a value, never a flag; turning one
into a verdict needs the `findings` structure, which does not exist yet.

**Debt this left standing, none of it created by that work:**

- **`SignalLevelMetrics` accepts `inf`/`NaN`** when a file carries finite-but-extreme samples — found in
  passing while proving consumer isolation, and worth its own decision rather than a quiet patch.
- **The waveform still reads the file for itself**, so an inspection performs two sample reads rather
  than one. Migrating it onto the shared seam is the obvious next reduction and is tracked in
  `add-shared-pcm-read`'s deferred section.
- **VoiceOver still does not enter the report's contents** — a gap recorded since the waveform slice.
  Every section added since inherits it, and no pass has ever been claimed.
- **Deferred metrics**, each named rather than forgotten: LUFS and loudness range, crest factor,
  significant maximum frequency, an analysis-engine-version field, and the inter-sample-clipping
  finding.
- **One unexplained test failure**, seen exactly once immediately after switching branches and never
  reproduced in twenty subsequent runs, including a first run after a full rebuild. Its name was not
  captured, which is a gap in how it was observed rather than a known defect; the same tree is green in
  CI. Worth watching rather than hunting blind.

**Next step:** nothing is in flight. The open threads below are the candidates.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
