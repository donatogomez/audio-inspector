# Give the Spectrum section a workspace

## Why

R5 gave Waveform a workspace and left Spectrum explicitly to R6 (its task 9.1). **Spectrum is still the
report page**: selecting it shows the same long scroll every unfinished section shows, and the drawing
it is named for is boxed into a **220 pt** plot — or, when two files are paired, two **140 pt** lanes —
whatever the window's height.

That matters more here than it did for the waveform. A spectrogram is two-dimensional: its vertical
extent *is* frequency resolution, and the model carries up to **512 bands**. Boxed at 140 pt a paired
lane shows barely a quarter of the bands it holds, and the question this drawing exists to answer —
*where does this file's energy stop?* — is a question about the top of that axis.

## Two findings, one inherited and one not

- **Inherited (R5 task 9.1):** the paired lane draws into a fixed strip. R5 fixed the waveform's and
  recorded that the spectral lane would want the same treatment.
- **Found here:** the paired spectrogram is drawn **with no legend at all**.
  `audio-two-file-visual-presentation` requires that both models be drawn *"with the same ramp and the
  same floor, and one legend describes both"* — and the single-file section carries a legend while the
  paired section carries none. A gradient without numbers states nothing, which is exactly why the
  single-file surface has one. This slice closes that.

## What changes

Selecting **Spectrum** presents a workspace: the drawing takes the height the section can offer, with
its frequency axis, its time axis and its legend; and for a pair, two lanes above the sentences naming
the shared extents and **one legend describing both**.

How much height is a value with a reason. The minimum keeps what the report page already gives the
drawing; the maximum is the model's own **band count**, because past one pixel per band a taller image
is upscaled rather than more detailed — and the raster is drawn with interpolation off, so upscaling
adds blocks, not information.

## What does not change

- **No transform is run, re-run or retained again.** No decoder, no PCM read, no STFT, no new raster
  strategy. `SpectrogramRaster.buffer(for:)` already takes no dimensions, so a resize cannot rebuild
  it — flexible height is free.
- **The absolute scale is untouched.** No normalisation, no auto-ranging, no auto-contrast, no per-file
  colour scale, no dynamic gain. The ramp, the floor (−120 dBFS) and the legend's ticks are the same
  constants, and the same ones for both files in a pair.
- **The frequency geometry is untouched.** A single file's axis still spans 0 Hz to **its own** Nyquist;
  a pair's still spans 0 Hz to the **greater** of the two, with each model occupying its own Nyquist as
  a fraction of that.
- **Above a file's own Nyquist stays outside the drawing.** No cell exists there, it keeps its
  achromatic treatment — which no colour on the ramp ever is — and it keeps its sentence. *This file
  cannot represent this range* and *this file was measured here and is very quiet* still do not look
  the same.
- **The drawing gains room and nothing else** (ADR-0026 §9): no zoom, pan, cursor, hover, frequency or
  time readout, scrubbing, selection, playback, overlay, difference spectrogram, subtraction,
  alignment, channel selector or image export.
- **The export, the DTOs and `schemaVersion` 1** are untouched; the spectrogram has never entered them
  and `Spectrogram` is not `Codable`.
- **R1–R5 are unchanged.** Overview keeps the transitional report page until R7.
- **No comparison surface is built.** The workspace reads the comparison only to know which drawing to
  show — the choice `ReportVisuals` already makes.
