# Design — the Waveform workspace

## 1. The pipeline, reconstructed

Read off production, not remembered. **Nothing in this chain is R5's to change.**

```
file → one shared PCM read (ADR-0021) → WaveformEnvelopeAccumulator
     → WaveformEnvelope → WaveformState → InspectionPresentation.waveform
     → RootView.waveformPresentation(for:) → WaveformPresentation → WaveformDrawing
```

`WaveformEnvelope` carries `buckets`, `frameCount`, `channelCount` and nothing else: no view width, no
normalisation factor, no sample rate, no URL. Buckets are capped at **2048** and never exceed the frame
count; each carries the **minimum and maximum across all channels** — never an average, because two
channels in opposing phase would cancel — on the sample scale `[-1, 1]`, **unnormalised** and
**unclamped**. It is `Sendable` and deliberately **not** `Codable`: the waveform never enters the
export.

For a pair:

```
comparedVisuals → RootView.pairedVisualsPresentation(for:)
                → PairedWaveformPresentation(axis:first:second:)
axis ← PairedWaveformAxis(first:second:) from each side's PCMStreamDescription
       (seconds = frameCount / sampleRate, shared extent = the greater)
```

`PairedWaveformLane` has **three** cases and no `loading`: a lane belongs to a pair, and a pair exists
only once both files have settled.

**Which drawing is shown is already decided once, for both drawings together**, by
`RootView.reportVisuals(for:in:)` → `ReportVisuals`. The workspace reads that same value, so it cannot
disagree with the report page about whether this is one file or two.

**R5 therefore needs no new decode, no new read, no new envelope and no new retention.** Verified
against production before any code was written; had it needed one, this slice would have stopped.

## 2. The overlap: the real cause, proven

`Sources/FeatureAnalysis/PairedVisualsView.swift`, `PairedWaveformSection.lane`:

| | |
|---|---|
| The box | `GeometryReader { … }.frame(height: 96)` |
| What is put in it | `WaveformSection(presentation: lane.asSingle)` — a `VStack(spacing: 8)` of **drawing + headline + detail** |
| What that needs | 96 (the drawing's own `.frame(height: 96)`) + 8 + ~14 ≈ **118 pt** |
| What happens | `GeometryReader` does not clip; ~22 pt of prose is drawn **outside** the box, over the next sibling |

The colliding sentence for a settled envelope is `WaveformCopy`'s
*"Amplitude over the whole file, combined across N channels."* — it lands on the lane's own
*"This file carries no audio beyond here."* or on the next lane's *"Second file"*. That is precisely
the reported symptom.

**It is not the 96 pt that is wrong; it is putting a composite inside a box sized for one of its
parts.** Raising 96 to 112 would move the collision to the next accessibility text size, which is why
that fix is refused below.

There is a second, quieter fault in the same place: `PairedVisualsCopy.waveform` **already** computes
this lane's `headline` and `detail`, from the same `WaveformCopy.text` call, and the lane renders
neither — it delegates to the section nested inside it. One sentence with two owners, and the owner
that draws it is the one that has no room.

### The correct shape already exists, twenty lines below

`PairedSpectrogramSection.lane`, in the same file, does it right:

```swift
GeometryReader { proxy in
    plot(lane, geometry: geometry, in: proxy.size)   // the drawing, and only the drawing
}
.frame(height: 140)
if let headline = text.headline { Text(headline) }   // siblings, in normal flow,
if let detail = text.detail { Text(detail) }         // rendered by the lane's own copy owner
if let outOfRange = text.outOfRange { Text(outOfRange) }
```

Its `GeometryReader` holds a **drawing**, not a composite, and its prose is laid out as siblings by
`PairedVisualsCopy` — so it has no overflow and never had one. **The waveform lane is the deviation,
not the pattern.** That settles what the fix should be: not an invention, but converging on the shape
its sibling in the same file already has.

## 3. The fix, and why it is structural

The lane stops embedding `WaveformSection`. It renders, as ordinary siblings in its own `VStack`:

1. `attribution` — which file this is, by position
2. the **drawing alone**, at the lane's measured width and the lane's own plot height
3. `headline` / `detail` — **the strings `PairedVisualsCopy` already produced**
4. `outOfRange` — what the rest of the lane means, when there is a rest

Nothing is nested inside a frame sized for something else, so there is nothing left to overflow. The
plot's height is the *plot's*, and the prose is measured by the layout like any other text — at any
accessibility size, in any window.

**What was refused**, and why each is a fix that expires:

| Refused | Why |
|---|---|
| 96 → 112 pt | moves the collision to the next text size |
| an offset or negative padding | tuned to one string in one locale at one text size |
| truncating *First file* / *Second file* | the attribution is the one thing that says which lane is which |
| shrinking the font until it fits | the surface must stay legible at accessibility text sizes |
| clipping the `GeometryReader` | hides the sentence instead of showing it — the capability requires it *stated* |

**The regression guard is structural, not visual.** A test asserts that the paired lane builds no
`WaveformSection` and declares no fixed-height frame around a `GeometryReader`, and that the lane's own
copy owner is what renders its prose. That is a property of the source a test can read; the collision
itself is only observable in a rendering, which is why the old code passed every test it had.

## 4. Plot sizing, from the layout rather than from taste

The window's minimum is **720 × 480**. The shell around the section costs, at that minimum:

| | |
|---|---|
| section navigation | ≈ 50 pt |
| two dividers | 2 pt |
| the bottom action bar | ≈ 46 pt |
| the workspace's own padding | 2 × 24 pt |
| **left for content** | **≈ 334 pt** |

From that budget:

- **Single**: prose ≈ 34 pt, so a plot minimum of **140 pt** leaves room to spare and is already
  half again the 96 pt strip it replaces.
- **Paired**: two lanes, each costing ≈ 16 (attribution) + ≈ 34 (prose) + 8 (spacing) ≈ 58 pt of text,
  plus the shared-extent line ≈ 16 pt. Two plot minimums of **90 pt** fit inside 334 with margin.

Both flex upward with the window. Both are **capped** — 420 pt single, 260 pt per lane — and the cap is
not decoration: an envelope's vertical information is bounded by the amplitude scale, not by pixels, so
past a certain height a waveform stops telling the reader anything new and starts making the prose that
explains it feel unmoored at the bottom of a tall empty box. The cap is where the drawing stops being
helped.

**No `ScrollView`.** A flexible height inside one collapses to the content's ideal, which is the bug
this section exists to fix. The workspace fills the section instead, and the plot is the part that
yields when something else needs room — which is the right priority when the prose is what carries the
meaning.

**The free space is shared, not pooled below**, and this was found by looking rather than by reasoning.
Rendered at 1440 × 900, two capped lanes left roughly 350 pt empty beneath them, and the surface read as
truncated rather than as composed — a workspace whose premise is using the space, visibly not using it.
The caps are right and stay; what was wrong was anchoring the content to the top. Two zero-minimum
spacers now centre what is there and collapse to nothing when there is no room to give, so a small
window still lays out from the top and a tall one looks deliberate.

## 5. Three architectures, and the one chosen

### A — a dominant plot with minimal metadata above

One line of identity, then the plot filling everything below it. **Rejected.** It has nowhere honest to
put a lane's *absent* or *failed* sentence, and for a pair it has nowhere to put the out-of-range
sentence that the shared axis makes necessary. A very large bare canvas also reads as an editor: the
emptier and more dominant the plot, the more it invites the click that does nothing.

### B — a dominant plot with one framing legend outside the drawing

All the words collected into a single band, shared by both lanes when paired. **Rejected**, and for a
sharper reason than layout: a lane's absence, failure and out-of-range sentences belong to **that
lane**. Collected into a shared band they must be matched back to a lane by order, which is exactly the
correlation ADR-0025 refuses to make a reader perform, and it would weaken the accessibility contract
that each drawing is one element labelled with its own file.

### C — a technical canvas: compact header, flexible plot, per-lane words — **chosen**

Each lane is a self-contained unit: its attribution, its plot, its own words. A single file is that
unit once; a pair is it twice, above the one line naming the shared extent.

|  | A — dominant plot | B — shared legend | C — per-lane units |
|---|---|---|---|
| Single file | good | good | good |
| Paired | no home for lane prose | prose matched by order | prose beside its own lane |
| 720 × 480 | plot dominates, prose squeezed | prose band competes | budgeted, both fit |
| Medium / large | plot grows | plot grows | plot grows, prose fixed |
| Accessibility | one element per drawing | weakened by the shared band | one element per lane, unchanged |
| Reads as an editor | **highest risk** | moderate | low — prose frames every plot |
| Suggests absent interaction | yes | some | no |
| Fixes the overlap | incidentally | incidentally | **by construction** |

C is also the only one that makes the defect unrepresentable rather than merely absent: the words are
never inside a box sized for the drawing, because the words and the drawing are siblings.

## 6. The information architecture

- **No section title.** The picker already says *Waveform*; R3 and R4 set the precedent of not repeating
  it, and the prose line beneath each plot already names the artefact.
- **Single file:** the plot, then *"Amplitude over the whole file, combined across N channels."* —
  or, in place of a plot, the sentence for whichever state it is in.
- **Paired:** *First file* → plot → its prose → its out-of-range sentence; the same for *Second file*;
  then one line naming the shared extent. Exactly the order the report page uses today.
- **File identity is not repeated.** The attribution is positional — *First file* / *Second file*, the
  strings `ComparisonCopy` already owns — and no name, path, parent directory or bookmark appears.
- **No method line, no legend, no axis ticks.** A tick every *n* seconds would assert a precision the
  drawing does not support; the shared extent is stated as a sentence, as it is today.

## 7. What the workspace may not gain

Room is not a power (ADR-0026 §9, `waveform-visualization`'s fourth requirement, and
`audio-two-file-visual-presentation`'s ninth). The drawing keeps `allowsHitTesting(false)` and the
workspace adds **no** gesture, zoom, pan, cursor, playhead, scrubbing, selection, loop, transport,
playback, hover readout, interactive timestamp, alignment, overlay, difference view, correlation,
similarity, normalisation, gain matching, recomputation, export or channel selector. A guard test
sweeps the new sources for that vocabulary rather than trusting the diff.

## 8. Capability ownership

Two capabilities are modified, and the third deliberately is not:

- **`audio-file-inspection`** — that Waveform *is* a section, that it is the only place the drawing
  appears while selected, and that filling it computes nothing. This is where R2, R3 and R4 put the same
  contract.
- **`audio-two-file-visual-presentation`** — that a lane's words are laid out **clear of** the drawings.
  The capability already requires the out-of-range regions and absences to be *"stated in words"*; a
  sentence drawn on top of another is not stated, so this sharpens an existing requirement's own
  premise rather than adding a new idea.
- **`waveform-visualization` is not touched.** Its fourth requirement already forbids playback, zoom,
  scrubbing, selection and a cursor **unconditionally**, and already fixes the one-element accessibility
  contract and the words-not-empty-area rule. Those bind the workspace entire. Restating them for a
  bigger drawing would duplicate a canonical contract, which is exactly what this project's archive
  discipline refuses.

## 9. Deferred

- **A comparison surface** — R8. This slice reads the comparison only to choose between one drawing and
  two, which is the choice `ReportVisuals` already makes.
- **Spectrum's workspace** — R6. `PairedSpectrogramSection` needs **no overlap fix** — §2 shows it
  already lays its prose outside the plot — but it still draws into a fixed 140 pt strip and will want
  the same flexible sizing this slice gives the waveform. R5 does not touch it: R6 owns that surface,
  and changing it here would be one slice reaching into the next one's.
- **The full accessibility and responsive passes** — R9, including the behaviour at the largest
  accessibility text sizes, where the prose can still out-grow the budget above.
