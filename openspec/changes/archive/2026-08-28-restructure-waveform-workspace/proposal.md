# Give the Waveform section a workspace

## Why

R1 built the workspace's five sections. R3 and R4 filled the two made of words. **Waveform is still the
report page**: selecting it shows the same long scroll every unfinished section shows, and the drawing
it is named for sits in a **96 pt** strip near the top of that page, the same height whether the window
is 480 pt tall or 1400.

Two things are wrong there, and the second is a defect rather than a shortcoming:

- **A drawing in a 96 pt strip is a thumbnail, not a workspace.** ADR-0026 §9 makes Waveform a section
  precisely so the drawing has room; today the section exists and the room does not.
- **The paired waveform's text overlaps.** It was seen during ADR-0025's manual pass, reported, and
  deliberately left for this slice. The cause is structural and is stated below.

## The overlap, and its actual cause

`PairedWaveformSection.lane` places the **whole** single-file section — the drawing *and* the two lines
of prose beneath it — inside a `GeometryReader` frozen at `.frame(height: 96)`, which is the height of
the **drawing alone**:

```swift
GeometryReader { proxy in
    WaveformSection(presentation: lane.asSingle)   // drawing + headline + detail
        .frame(width: proxy.size.width * fraction, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
}
.frame(height: 96)
```

`WaveformSection` needs about 118 pt for an envelope — 96 for the drawing, 8 of spacing, and a line
reading *"Amplitude over the whole file, combined across N channels."* A `GeometryReader` does not clip,
so those last ~22 pt are drawn **outside** the box, on top of whatever follows: the lane's own *"This
file carries no audio beyond here."*, or the next lane's *"Second file"*. That is exactly the reported
symptom.

It is doubly wrong. `PairedVisualsCopy.waveform` **already computes** each lane's `headline` and
`detail` — the same strings, from the same `WaveformCopy` call — and the lane never renders them,
delegating instead to the section embedded inside it. One sentence, two owners, one of them boxed too
small.

## What changes

Selecting **Waveform** presents a workspace: the drawing takes the height the window can give it,
above a line saying what it is and, for a pair, the shared extent both lanes are measured against.

The paired lane is rebuilt so that **only the drawing is inside the measured area**; the lane's
attribution, its state sentence and its out-of-range sentence are laid out as siblings, in normal flow,
by the copy owner that already produces them. There is no nested fixed height left to overflow.

## What does not change

- **No envelope is produced, recomputed or retained again.** No decoder, no PCM read, no accumulator.
  The workspace consumes the value the composition root already builds for the report page.
- **The drawing gains room and nothing else** (ADR-0026 §9). No zoom, no pan, no cursor, no playhead,
  no scrubbing, no selection, no playback, no hover readout, no alignment, no overlay, no difference
  view, no normalisation and no waveform export.
- **The bucket arithmetic, the amplitude scale and the shared time axis are untouched.**
  `WaveformGeometry` and `PairedWaveformAxis` are not edited. A shorter file still ends where its audio
  ends, and the remainder of its lane still carries no drawn value and still says so in words.
- **The export, the DTOs and `schemaVersion` 1** are untouched; the waveform has never entered them.
- **R1's navigation, R2's pre-inspection surface, R3's Details and R4's Measurements** are unchanged.
  Overview and Spectrum keep the transitional report page until their own slices.
- **No comparison surface is built.** The workspace reads the comparison only to know which drawing to
  show — the choice `ReportVisuals` already makes for the report page.
