# restructure-empty-state

**R2** of the redesign governed by
[ADR-0026](../../../docs/adr/0026-inspection-workspace-information-architecture.md) and sequenced by
[`restructure-inspection-workspace`](../restructure-inspection-workspace/), which merged R1 — the five
sections and the selection that moves between them.

This slice re-lays-out the surface a person sees **before a report exists**: the starting screen, the
in-progress feedback, and the recoverable failure. Those are three states of **one shell**, not three
screens, and none of them is a section of the workspace R1 built.

It moves no report content, adds no feature, and changes nothing about how a file is chosen, accessed or
read. Its whole subject is what the window says while there is nothing to show.
