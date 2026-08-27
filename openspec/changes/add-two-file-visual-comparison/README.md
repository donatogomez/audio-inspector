# add-two-file-visual-comparison

Show two files' waveforms and spectrograms together, on **shared absolute axes**, using the pictures the
second file's single read already produced and the flow currently throws away. It **pairs and presents**;
it publishes no verdict about the two images — no *same*, no *different*, no *similar*.

While a settled pair exists, the paired drawings **stand in for** the first file's own waveform and
spectrogram sections rather than being added beneath them: showing the same file twice, at two different
geometries, would put two answers to one question on one screen. The technical comparison and the
measurement comparison are untouched and stay visible. When the pair goes, the single-file drawings come
straight back — from the values already in memory, with nothing read or computed again.

Governed by [ADR-0025](../../../docs/adr/0025-two-file-paired-visuals.md), which is `Proposed` and whose
promotion depends on this change: reuse without recomputation, an unmixable pair, and two manual axis
checks (group 10).

**Nothing here is implemented.** This directory is the contract and the plan.
