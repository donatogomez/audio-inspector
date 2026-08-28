# restructure-waveform-workspace

**R5** of the redesign governed by
[ADR-0026](../../../docs/adr/0026-inspection-workspace-information-architecture.md) and sequenced by
[`restructure-inspection-workspace`](../restructure-inspection-workspace/). R1 built the five sections;
R2 rebuilt the surface before a report; R3 gave **Details** its content and R4 gave **Measurements**
its own. This slice gives **Waveform** a workspace.

It is the first section whose content is a **drawing**, so it is the first that needs room rather than
order. ADR-0026 §9 says what that room buys and what it does not: *"A section gives each drawing room.
It gives it nothing else."*

**It moves a drawing; it draws nothing new.** The envelope, the bucket arithmetic, the amplitude scale,
the shared time axis and every sentence are the ones production already produces. No file is read again,
no envelope is recomputed, and nothing becomes interactive.

It also closes the one cosmetic defect the umbrella assigned here: the **paired waveform's overlapping
text**.
