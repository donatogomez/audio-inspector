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

**Focus:** `add-waveform-visualization` is **open and fully specified; nothing is implemented.** The
four artifacts are written and `openspec validate --all --strict` is green, ADR-0015 exists in
`Proposed`, and 3 of 57 tasks are done — all three of them the contract itself. Design work only, on
`docs/add-waveform-visualization-design`. No functional code.

**Status:** Unlike every earlier attempt at this slice, the decoding strategy is not a hypothesis. The
spike is integrated and **reproducible** — a clean rebuild from `main` of
`Spike/validate-native-pcm-decoding` regenerates every SHA-256 recorded in
`docs/spikes/2026-08-05-native-pcm-decoding-validation.md` — so ADR-0015 cites measurements instead of
asserting them.

`AVAudioFile` opens and fully decodes
WAV, AIFF, ALAC, FLAC and AAC to one uniform processing format — `'lpcm'` float32, planar — with the
frames read matching the declared `length` exactly in all five. Multichannel keeps channel identity and
order, and native float PCM round-trips values beyond ±1 untouched, so neither clipping nor
normalisation happens on the way in.

The finding that changes how code must be written is smaller and sharper: **the buffer region past
`frameLength` is never safe.** For four formats it holds whatever the caller left there; for AAC it is
overwritten with content that is deterministic, content-derived, and about 1 % of the signal's level —
so a reader that took `frameCapacity` frames would draw something plausible and wrong, consistently,
and only for some files. Reading also cannot stop by watching for a zero-length read: past the end,
`read(into:)` throws a bare error carrying no `NSError`, indistinguishable from a real failure. The
rules that follow are `framePosition < length` to bound the loop and `frameLength` to bound the data.

**The one thing the spike could not do is MP3**, because macOS has no MP3 encoder and the spike wrote
its own fixtures. It is a target format and the waveform must decode it, so it is now group 0's
mandatory evidence gap — verified against the **production** adapter, never by extending the spike and
never asserted from `afconvert`, FFmpeg or documentation. **ADR-0015 stays `Proposed` until that case
is resolved** and the manual validation is done.

**Next step:** Implement group 0's acceptance matrix and groups 2 and 3 — the domain port and the
`AVAudioFile` adapter. Nothing else is started.

**Why:** Everything later — levels, loudness, spectra — reads samples through this seam. Building it
under a min/max reduction means a defect in the seam cannot hide behind a defect in the maths.

**Open questions / threads:** Three are left to group 0's measurements rather than guessed: the chunk
size, whether MP3 exposes a usable `length`, and whether a secondary technical detail beside the drawing
adds value. The reduction lives in Media, and what would overturn that is a second consumer of the same
decoded stream — the first level metric or the first FFT makes a chunked-decode port a real seam.

**The report's manual accessibility validation is still open and still not done.** It was deliberately
deferred when `improve-report-presentation` was archived and is now **scoped into group 7** of this
slice, to be performed once over the finished surface including the waveform, rather than twice over a
moving one. Nothing about it is marked done and no evidence for it exists.

Still not started, each needing its own change: spectrogram, playback, zoom, editing, and the
per-property explanations. Also carried forward and deliberately **not** mixed into this slice: the drag
sources never exercised — iCloud files, aliases, symlinks, app bundles and Mail file promises — open
against ADR-0014. Plus the pinned `en_US` locale not following the user's region, and
`Choose another file…` still at the foot of the window while exporting lives in the toolbar.

---
_Last touched: 2026-08-05. Overwrite freely; empty is fine._
