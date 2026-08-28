# Design — the Spectrum workspace

## 1. The pipeline, reconstructed from production

Read off the code and the accumulator, not remembered. **None of it is R6's to change.**

```
file → one shared PCM read (ADR-0021) → SpectrogramAccumulator (Accelerate/vDSP)
     → Spectrogram → SpectrogramState → InspectionPresentation.spectrogram
     → RootView.spectrogramPresentation(for:) → SpectrogramPresentation → SpectrogramPlot
```

| | verified value |
|---|---|
| FFT size | **2048** (`SpectrogramAccumulator.fftSize`) |
| hop | **512** (`SpectrogramAccumulator.hop`) |
| window | **Hann**, denormalised, magnitude scaled by `1 / windowSum` |
| transform bins | `fftSize / 2 + 1` = **1025** |
| model resolution | ≤ **1024 columns** × ≤ **512 bands** (`SpectrogramGridMapping.defaultMaximumColumnCount` / `…BandCount`) |
| reduction | by **maximum**, never an average, in both dimensions |
| scale | **dBFS, absolute**, floor **−120** (`Spectrogram.floorDecibels`) |
| channels | transformed **separately**, combined by **maximum magnitude per bin** |
| frequency | linear, 0 Hz → `nyquist = sampleRate / 2` |
| conformances | `Sendable, Equatable` — deliberately **not `Codable`** |
| raster | `SpectrogramRaster.buffer(for:)` takes **no dimensions**; built once per model in `.task(id: model)`, off the main actor |

For a pair: `PairedSpectrogramAxes(first:second:)` takes each side's `PCMStreamDescription`, composes
`PairedWaveformAxis` for time (so a waveform lane and a spectral lane cannot disagree about duration),
and computes `sharedNyquist = max(nyquists)` with `frequencyFraction = nyquist / sharedNyquist` and
`outOfRangeFraction = 1 − frequencyFraction`.

**R6 therefore needs no new read, decode, STFT, retention or spectral conversion.** The raster being
dimension-independent is what makes a flexible height free: resizing re-draws an existing image and
cannot rebuild it. Verified before any code was written; had it needed one, this slice would have
stopped.

## 2. The drawing as it stands

### Single — `SpectrogramSection`

| | |
|---|---|
| plot | `plotHeight = 220`, fixed |
| frequency axis | left gutter **56 pt**, marks from `SpectrogramAxes.frequencyMarks(nyquist:)`, 0 Hz at the bottom to the file's own Nyquist |
| time axis | bottom gutter **18 pt**, marks from `SpectrogramAxes.timeMarks(duration:)` |
| legend | ramp swatches + ticks `[−120, −90, −60, −30, 0]` + *"Energy in dBFS. Darker is quieter; lighter is louder."* |
| accessibility | cells, axes and legend `accessibilityHidden(true)`; **one element for the whole section** |
| interaction | `allowsHitTesting(false)` |
| states | loading · model · absent · failed; a model with zero columns is a statement, not an absence |

### Paired — `PairedSpectrogramSection`

| | |
|---|---|
| lane plot | `GeometryReader { plot(...) }.frame(height: 140)`, fixed |
| out-of-range | a `Rectangle().fill(outOfRangeTreatment)` filling the lane, with the model image drawn over the bottom `frequencyFraction` of it |
| treatment | `(0.32, 0.32, 0.32)` — **achromatic**, which no colour the ramp produces ever is |
| axes | **no drawn axes**; two sentences name the shared extents instead |
| legend | **none — and that is the gap this slice closes** |
| accessibility | one element per lane, naming the artefact and the file |

**R5's finding holds and is re-verified: the spectral lane already lays its prose outside the plot.**
Its `GeometryReader` holds `plot(...)` and nothing else; the attribution, headline, detail and
out-of-range sentence are siblings. **There is no overlap here to fix, and none is invented.** What it
shares with the waveform lane is only the fixed strip.

## 3. The legend gap

`audio-two-file-visual-presentation` — *Draw both spectral models on one absolute energy scale* —
requires: *"both are drawn with the same ramp and the same floor, **and one legend describes both**"*.
`PairedSpectrogramSection` renders no legend, in the workspace or on the report page. The single-file
section has one, for the reason its own comment gives: *"A gradient without numbers states nothing"*.

So the pairing today shows a colour scale it never explains. This slice adds **the existing
`SpectrogramLegend`, unchanged**, once beneath both lanes — not a new legend, not a redesigned one, and
not a second set of numbers that could drift from the first. Because it goes into
`PairedSpectrogramSection` rather than only into the workspace, the contract is met everywhere the
pairing appears, which is the same reasoning R5 used for the overlap.

## 4. Plot sizing, derived rather than chosen

The window's minimum is **720 × 480**, and the shell costs ≈ 50 (navigation) + 2 (dividers) + 46
(action bar) + 48 (padding) ⇒ **≈ 334 pt of content**, the budget R5 established and this slice reuses
rather than re-deriving.

**The maximum is the model, not taste.** A spectrogram carries at most **512 bands**. Drawn taller than
512 pt the image is upscaled past one pixel per band — and it is drawn with `interpolation(.none)` and
`antialiased(false)`, deliberately, so upscaling adds blocks rather than detail. That makes 512 the
height where the drawing stops being helped, and it is a property of the data rather than an opinion.

| | minimum | maximum | why |
|---|---|---|---|
| single | **220** | **512** | the minimum is exactly what the report page gives it today, so nothing is lost at the smallest window; the maximum is the band count |
| paired lane | **80** | **256** | two lanes, their prose, the shared-extent sentences and the legend have to fit the same budget; the maximum is half the band count, so two lanes together never exceed one full-resolution image's worth of height |

Checked against the budget, for the worst case — and **the worst case is one out-of-range sentence, not
two**: the higher Nyquist always occupies the whole shared axis, so only the lower-rate lane can carry
one. That is a property of `PairedSpectrogramAxes`, and a test asserts it rather than the arithmetic
assuming it.

```
lane with an out-of-range sentence   18 attribution + 80 plot + 18 detail + 18 out-of-range = 134
lane without one                     18 attribution + 80 plot + 18 detail                   = 116
                                     + 12 spacing + 36 shared-extent sentences + 30 legend
                                                                             total = 328  ≤  334
```

**A first draft of this budget was wrong**, and the test caught it: it assumed both lanes could carry an
out-of-range sentence and mis-added the total to 330 when the same terms give 366. The minimum came down
from 90 to 80 as a result, which is what the budget actually leaves rather than what looked comfortable.

Single, worst case: `220 plot + 18 time axis + 30 legend + 34 prose = 302 ≤ 334`.

**No `ScrollView`**, for R5's reason: a flexible height inside one collapses to the content's ideal.
The plot is the part that yields when the prose needs room, which is the right priority when the prose
carries the meaning.

## 5. Large windows

R5 found, by rendering, that capped content anchored to the top of a tall window reads as truncated.
The same two zero-minimum spacers are used here, so free space is shared rather than pooled below. The
caps leave much less of it than the waveform's did: at 1440 × 900 (≈ 754 pt of content) a single plot
takes 512 of 754, and a pair takes 2 × 256 plus 186 of prose — 698 of 754.

## 5a. What the render showed, and what it could not

Ten renders through the same external harness R5 used — three window sizes, single and both paired
cases, plus an absent one — nothing added to the repository.

**Confirmed by eye**, in the paired cases: the out-of-range region is unmistakably distinct from the
floor (an even grey band above the model, against the ramp's near-black inside it); only the lower-rate
lane carries one, and it carries its sentence; the shared axis reaches the higher Nyquist; the legend
is present with its ticks and its caption; both lanes, both sets of prose, both shared-extent sentences
and the legend fit the 720 × 480 minimum with no overlap and no clipping; and at 1440 × 900 the lanes
reach their cap with the free space shared rather than pooled.

**Two limitations of the harness, declared rather than worked around:**

- **The single-file cells do not appear in a render.** They are produced by `.task(id: model)`, and
  `ImageRenderer` renders synchronously and never runs a SwiftUI task, so the raster stays `nil` and the
  area draws `Color.clear`. The paired lanes render because their path calls `SpectrogramRaster.image(for:)`
  synchronously in the body. **Neither line is touched by this slice**, and the single plot being briefly
  empty before its raster lands is existing, documented behaviour — so the single case's *layout*, its
  frequency axis, its time axis and its legend are validated here, and its *cells* are not.
- **The harness composites no window background**, so one render came back in a dark appearance with
  secondary text against black. That is the renderer's, not the section's.

## 6. Three architectures, and the one chosen

### A — a dominant plot with peripheral axes and legend

The plot fills the section; the frequency axis, time axis and legend sit around its edges as chrome.
**Rejected.** It is the arrangement that most resembles an audio editor, and the resemblance is the
problem rather than the look: the larger and more instrument-like a spectrogram is, the more strongly a
peripheral axis invites the drag, the hover readout and the zoom that this surface refuses. It also has
nowhere honest to put a lane's *absent* or *failed* sentence.

### B — a technical canvas: compact header, flexible plot, legend below

A header line, the plot, then the legend and the words. **Rejected for the pair, not for the single.**
A pair needs each lane's absence, failure and out-of-range sentence attached to *that* lane; a single
header cannot carry two lanes' states, and collecting them would force the reader to match sentence to
lane by order — the correlation ADR-0025 refuses to ask for.

### C — per-unit composition, spectral rather than borrowed — **chosen**

One file is one unit: plot with its own axes, its legend, its words. A pair is two lanes — each with
its attribution, its plot, its own words — above the shared-extent sentences and **one** legend.

This is *not* R5's shape cloned. The waveform lane needed no axes and no legend, so its unit was
attribution → plot → prose. The spectral unit differs in three ways that matter:

- the **single** case carries drawn axes inside the plot's own area (a left gutter and a bottom gutter),
  which the waveform has nothing equivalent to;
- the **paired** case deliberately has *no* drawn axes and states its extents in sentences instead —
  two lanes each with their own gutters would spend the budget on chrome and would invite comparing one
  lane's ticks against the other's;
- the legend is **shared** by the pair and **owned** by the single, so it sits at a different level in
  the two cases.

|  | A — dominant plot | B — one canvas | C — per-unit |
|---|---|---|---|
| Single | good | good | good |
| Paired | no home for lane states | states matched by order | states beside their lane |
| 720 × 480 | chrome crowds the plot | fits | budgeted, fits (§4) |
| 1440 × 900 | plot grows | plot grows | plot grows to the band count |
| Axes | peripheral, editor-like | inside | single: drawn · paired: stated |
| Legend | peripheral | below | single: its own · paired: one, shared |
| Accessibility | one element per drawing | weakened for the pair | one element per drawing, unchanged |
| Reads as an editor | **highest risk** | moderate | low |
| Absolute comparability | at risk from peripheral controls | kept | kept, and now explained by the legend |

## 7. The information architecture

- **No section title.** The picker says *Spectrum*; R3, R4 and R5 set the precedent, and the section's
  own words already name the artefact.
- **Single:** frequency axis + plot + time axis, then the legend, then the sentence describing it — the
  report page's own order, unchanged.
- **Paired:** *First file* → plot → its words → its out-of-range sentence; the same for *Second file*;
  then the shared time sentence, the shared frequency sentence, and **one legend**.
- **Out-of-range** keeps both of its carriers: the achromatic region **and** the sentence. Neither is
  removed, so the distinction never rests on colour alone.
- **File identity is positional** — *First file* / *Second file*, `ComparisonCopy`'s own strings. No
  name, path, parent directory or bookmark.

## 8. Floor versus out-of-range, kept structural

They are already two different **render paths**, not two colours that happen to differ:

| | how it is drawn | what it means |
|---|---|---|
| floor | a cell in the raster, at the ramp's lowest stop | measured here, and very quiet |
| out-of-range | a `Rectangle` of `outOfRangeTreatment`, with **no cell over it** | this file cannot represent this range |

The treatment is achromatic by construction and every ramp stop separates red from blue, so no ramp
value can equal it. This slice **changes neither**, and adds tests that assert the two are produced by
different paths rather than trusting that they currently look different.

## 9. Capability ownership — one, and the reasoning for the other two

- **`audio-file-inspection`** is modified: that Spectrum *is* a section, that it is the only place the
  drawing appears while selected, that room grants it no powers, and that an absent drawing is stated
  in words. This is where R2, R3, R4 and R5 put the same contract.
- **`audio-two-file-visual-presentation` is not modified.** Every paired property this slice touches —
  one ramp, one floor, **one legend describing both**, the shared frequency axis to the higher Nyquist,
  the out-of-range region distinguishable from the floor — is **already** a requirement there. R6
  *satisfies* the legend requirement rather than changing it, so adding a delta would restate a
  canonical contract.
- **`spectrogram-visualization` is not modified, and could not sensibly be.** It is **not a canonical
  capability**: it exists only inside `add-static-spectrogram-visualization`, which is still an **open,
  unarchived change** (73/89, its remaining tasks manual validation deferred by product decision).
  Writing a second delta against a capability another live change is still adding would create two
  competing sources for one spec, resolved only by archive order. R6 changes none of its semantics, so
  it needs nothing there — the same conclusion R5 reached about `waveform-visualization`, for a
  different reason.

## 10. Deferred

- **The Inspection Overview** — R7. Overview keeps the transitional report page.
- **A comparison surface** — R8. This slice reads the comparison only to choose between one drawing and
  two.
- **The full accessibility and responsive passes** — R9, including the largest accessibility text
  sizes, where a paired lane's prose can out-grow the budget in §4.
- **ADR-0016's promotion and the spectrogram change's own closure** — `add-static-spectrogram-visualization`
  stays open with its manual battery deferred; nothing here promotes it or closes it.
- **Splitting `PropertyDisplay.detail`** — inherited from R3, restated by R4 and R5.
