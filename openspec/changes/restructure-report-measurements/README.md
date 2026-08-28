# restructure-report-measurements

**R4** of the redesign governed by
[ADR-0026](../../../docs/adr/0026-inspection-workspace-information-architecture.md) and sequenced by
[`restructure-inspection-workspace`](../restructure-inspection-workspace/). R1 built the five sections;
R2 rebuilt the surface before a report; R3 gave **Details** its content. This slice gives
**Measurements** its own.

Measurements holds the four figures the inspection derives from the file's **samples** — the signal
levels, the true peak, the integrated loudness and the programme bandwidth — where Details holds what
the file's **header** declares. They are four separate measurements produced by four methods, and this
section is where a reader reads them as one body of work rather than as four boxes at the bottom of a
page.

**It moves measurements; it measures nothing.** Every value, unit, absence, failure, per-channel
breakdown, resolution and method sentence is the one the four measurement surfaces already produce. No
sample is read, no accumulator is run, and nothing is rounded, converted or re-worded on the way.
