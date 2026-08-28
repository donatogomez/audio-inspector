# restructure-inspection-workspace

The umbrella for the UX/UI redesign governed by
[ADR-0026](../../../docs/adr/0026-inspection-workspace-information-architecture.md): one scrolling page
becomes **Overview · Measurements · Waveform · Spectrum · Details**, a comparison becomes a **mode** of
the same five sections rather than more page underneath them, and the selected section becomes
presentation state the composition root owns.

**It implements the shell and nothing else** — the five sections and the selection that moves between
them — because that behaviour is architecture rather than any slice's content. Everything a section
*contains* is re-laid-out by the slices that follow, each its own small PR against a settled
architecture. It also carries the slice map, the contracts that must survive the redesign, and the
deferrals.

Slices: **R1 is this change** · **R2** Empty · **R3** Details · **R4** Measurements · **R5** Waveform
workspace · **R6** Spectrum workspace · **R7** Inspection Overview · **R8** Comparison mode · **R9**
responsive, accessibility and the manual pass. R0 — `extract-exportable-measurements` — is already
merged and outside this sequence.

**R1 is merged** (PR #52, merge commit `9a5f006`). **R2 is open** as its own change,
[`restructure-empty-state`](../restructure-empty-state/), and is specified but not implemented. R3–R9
are not started.
