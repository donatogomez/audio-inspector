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

**Focus:** None in progress. The **native PCM decoding spike is integrated and closed**; no OpenSpec
change is open and the waveform itself has not been started — no branch, no change, no code.

**Status:** The spike answered the question it was built for, and its evidence now lives in the
repository rather than in a conversation: the report is `docs/spikes/2026-08-05-native-pcm-decoding-validation.md`
and the package that produced it is `Spike/validate-native-pcm-decoding/`. It is **reproducible** — a
clean rebuild from `main` regenerates every recorded SHA-256 exactly, which is what makes the findings
citable by an ADR instead of merely asserted. The package is throwaway by design and its deletion
criterion is written into the report: it goes once ADR-0015 exists and the waveform slice's own tests
cover these observations.

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

MP3 remains **manual, not CI coverage** — macOS has no MP3 encoder and CI installs no FFmpeg, so a
gated test would skip on every run. Damaged files, cancellation, memory and isolation were **not**
exercised: they belong to the waveform slice's own tests, where they are cheaper to assert against real
code than against a throwaway package.

**Next step:** Open `add-waveform-visualization` on a branch from `main`. It needs a `MODIFIED` delta
scoping the accepted no-DSP requirement — which today forbids a waveform outright, in so many words — a
new `waveform-visualization` capability, and **ADR-0015** in `Proposed` covering the three
hard-to-reverse decisions: `AVAudioFile` over `AVAssetReader`, the `frameLength` invariant, and the
reduction living in Media. ADR-0003 is referenced, never edited.

**Why:** ADR-0003 adopted native-first but recorded its own sufficiency as an open hypothesis pending a
decoding spike. That hypothesis is now answered for decoding-to-an-envelope, and the answer is written
down where an ADR can cite it. Everything later — levels, loudness, spectra — reads samples through the
seam this evidence describes.

**Open questions / threads:** The reduction lives in Media, and what would overturn that is a second
consumer of the same decoded stream: the first level metric or the first FFT makes a chunked-decode port
a real seam. Whether a buffer-shaped type ever belongs in the pure domain is deliberately unanswered.

Still not started, each needing its own change: waveform, spectrogram, playback, zoom, editing, and the
per-property explanations. Carried forward from the presentation work: its manual accessibility checks
remain deliberately deferred, the pinned `en_US` locale does not follow the user's region, and
`Choose another file…` still sits at the foot of the window while exporting lives in the toolbar.

---
_Last touched: 2026-08-05. Overwrite freely; empty is fine._
