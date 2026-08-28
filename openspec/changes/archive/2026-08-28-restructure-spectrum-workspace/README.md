# restructure-spectrum-workspace

**R6** of the redesign governed by
[ADR-0026](../../../docs/adr/0026-inspection-workspace-information-architecture.md) and sequenced by
[`restructure-inspection-workspace`](../restructure-inspection-workspace/). R1 built the five sections;
R2 rebuilt the surface before a report; R3 and R4 filled the two made of words; R5 gave **Waveform** a
workspace. This slice gives **Spectrum** one, and it is the last section before the Overview.

The spectrogram is the redesign's densest artefact — two dimensions, an absolute colour scale, two
axes and a legend — so this section needs room more than any other. ADR-0026 §9 still fixes what that
room buys and what it does not: *"A section gives each drawing room. It gives it nothing else."*

**It moves a drawing; it transforms nothing.** The STFT, its resolution, the absolute dBFS scale, the
floor, the colour ramp, the frequency and time geometry and every sentence are the ones production
already produces. No file is read again, no transform is run again, and nothing becomes interactive.

It also closes a gap R6 found rather than inherited: the paired spectrogram was drawn **without a
legend**, though `audio-two-file-visual-presentation` requires one legend to describe both.
