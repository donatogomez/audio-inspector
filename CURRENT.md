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
**Thread complete, not yet published: `add-significant-bandwidth-measurement`.** Groups 1-8 are closed,
group 9 is deferred without pretence, and group 10 is done except the archive, which its own wording
places after merge. **ADR-0023 is `Accepted`** as of 2026-08-20.

**What exists.** A methodology decided by measurement on graded fixtures — −50 dB prominence against
each window's own peak, ≥ 10 % persistence, a 60 dB programme budget, a Hann window fixed in *time* at
~42.67 ms with 75 % overlap. A `SignificantBandwidth` domain value that carries no verdict. An
accumulator whose memory is constant in duration — 2.4 MB at 48 kHz, 8.7 MB at 192 — because counters
are stratified by each window's own peak rather than a spectrogram being kept. It is the sixth consumer
of the one shared PCM read, and the read count is still one. It is validated against production, shown
as its own section between the integrated loudness and the spectrogram, and exported under
`measurements.programmeBandwidth` at `schemaVersion` 1.

**What promoted the ADR, and what did not.** Its three literal conditions: the constants from graded
fixtures; the impulse control against *production* code, where a full-scale click inside a programme
leaves the reading identical and the turnover is pinned on both sides; and a person looking at the
surface, who saw the five fixtures read their pre-computed values and saw the file with a click in it
be indistinguishable from the file without. **The manual pass was narrower than ADR-0019's** — light,
dark, resize, a by-hand stale selection and a word-by-word vocabulary read were not reported, and are
recorded as unticked rather than inferred. That is in the ADR's `Promotion` section and in the manual
runbook, both of which say what is not claimed.

**Two containers were introduced, each on its own commit and each proved neutral.**
`InspectionAnalyses` for the flow, and `ReportMeasurements` for the export chain — the latter paying a
debt three separate notes had deferred to whoever added a fourth measurement, byte-identical across all
five existing combinations before anything was added to it.

**Deferred, and named**: a shared STFT stage and an average spectrum (one piece of work, waiting for the
second consumer), comparison between two files, and findings. None was started; none is ticked.

**Next step: publish.** Nothing is pushed, no branch tracks a remote, and no pull request exists. The
archive runs `after merge`, by task 10.2's own wording — not before.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded eleven
snapshots ago is unchanged and still not a thread.

---
_Last touched: 2026-08-20. Overwrite freely; empty is fine._
