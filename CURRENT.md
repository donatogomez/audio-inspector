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

**Focus:** `add-waveform-visualization`, on `feature/add-waveform-visualization`. The port, the
`AVAudioFile` adapter, the wiring and now the **static presentation** are implemented; the waveform is
drawn inside the report and the four gates plus the Xcode build are green. What is left is the MP3
evidence gap, the adapter's own test rows, and the manual validation.

**Status:** The drawing is one filled `Path` of one rectangle per bucket, not a continuous outline —
an outline interpolates between one bucket's extremes and the next's, drawing a value that was never
measured. The geometry is a pure mapper outside the `Canvas`, because a renderer closure cannot be
asserted and everything worth guaranteeing about it is arithmetic. **The visual clamp to `[-1, 1]`
applies to the coordinate it returns, never to the bucket it came from**; the envelope keeps values as
read.

`FeatureAnalysis` cannot see `FeatureImport`'s `WaveformState` — features depend on Domain and never on
each other — so it declares its own `WaveformPresentation` over the domain envelope and `RootView`
translates. That seam is the only place the two vocabularies meet, and it is pinned by a test.

**MP3 is closed, as local evidence only.** The production adapter decoded an FFmpeg-encoded stereo MP3
into an envelope identical at five chunk sizes, with the source byte-identical afterwards; the
measurements are in ADR-0015. **CI installs no FFmpeg, so that suite skips there and the skip is not
coverage** — the skip message says so, and the skip path was verified against a negative control rather
than assumed. MP3 also turned out to be the only format that exercises the `readFailed` path: LAME's
Xing header declares a duration a truncated file no longer has, and the adapter refuses rather than
half-drawing it.

**Group 7 is 7 of 10, and the three that are open are open for two concrete reasons.** The waveform's
own accessibility — single element, honest label, contrast in both appearances, nothing carried by
colour alone — passed, and so did the inherited checks on identifiers and colour. What did not happen:
**no mechanism was found to enlarge the app's type**, so 7.5 and 7.8 were only ever seen at the normal
size; and **interactive VoiceOver reached only the two actions**, so 7.7's traversal of the report was
never observed. Accessibility Inspector showed the tree is complete, which is not the same thing.

**Two of them need a decision rather than another attempt.** 7.5 and 7.8 ask for the system's largest
text sizes, and **macOS has no such thing for this app** — measured twice over: the preview canvas
offers only colour-scheme variants for a macOS destination, and `.dynamicTypeSize` has no effect on
macOS (identical rendered size from `.large` to `.accessibility5`). The criterion has no referent on
this platform, so it is either reworded to what macOS can exercise, or recorded as not evaluable under
the project's own rule for criteria that cannot be evaluated.

7.7 **failed and is now parked.** VoiceOver reaches only the two focusable controls and will not enter
the report's contents, while Accessibility Inspector reads the tree fine. One cause was tested and ruled
out — declaring the content an accessibility container changed nothing and was reverted rather than
kept. Whether the rest is a defect or a property of the testing environment is not established, and
**no more VoiceOver work belongs to this slice**: the traversal covers the whole report, most of which
predates the waveform, so this change should not be held open by it. It is carried as a known,
documented gap for a dedicated accessibility change.

**What this means for the change:** ADR-0015 stays `Proposed` — task 1.4 requires group 7's manual
validation done, and it is not. Group 0 is closed, MP3 included; groups 2–6 are closed. What remains is
a decision about how to finish: close group 8 and archive with the verification debt declared, as
`improve-report-presentation` was archived before it, or hold the change open. **That decision has not
been made and group 8 has not started.**

**Open questions / threads:** Whether MP3 exposes a usable `length` is still unknown. Whether a
secondary technical detail beside the drawing adds value was answered by building it — the channel
count is named because "the extremes across all channels" is incomplete without it, and nothing else
was added. The reduction lives in Media, and what would overturn that is a second consumer of the same
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
