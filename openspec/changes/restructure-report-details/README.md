# restructure-report-details

**R3** of the redesign governed by
[ADR-0026](../../../docs/adr/0026-inspection-workspace-information-architecture.md) and sequenced by
[`restructure-inspection-workspace`](../restructure-inspection-workspace/). R1 built the five sections;
R2 rebuilt the surface before a report. This slice gives **Details** its content.

Details is where a reader goes to see everything the inspection read and what became of each of it:
the technical properties, the file's own identity, the notes, and the result of the reading. It is
ADR-0026 §10's section — *"what the other four do not"* — and it is the reason the other four may be
short.

**It moves facts; it changes none.** Every value, every absence, every certainty state and every
sentence is the one the report already carried.
