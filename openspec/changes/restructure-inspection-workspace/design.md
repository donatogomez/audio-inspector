# Design — the redesign's map, and what it may not break

Every architectural decision here is **ADR-0026's**. This document sequences the work and names what has
to survive it. Where the two disagree, the ADR is right.

## 1. Why this change carries the navigation capability, and only that

The first shape tried was an umbrella that declared nothing — pure planning — so that no requirement
could be canonised before a slice delivered it. **OpenSpec refuses it**: a change must carry at least one
delta. That refusal is right, and it forced the better answer.

This change has observable behaviour of its own, and it is not any slice's content: **five sections
exist, one is selected, and the selection moves only when a new primary file arrives.** That is
architecture, it spans every slice, and no slice owns it. So this change carries the
`inspection-workspace-navigation` capability **and the shell that implements it** — what the plan called
R1 — and is archived when that is done, not when the last slice lands.

What it does **not** carry is any requirement about what a section contains. Each later slice modifies
the capability that already owns the content it re-lays-out, so nothing here duplicates
`audio-file-inspection`, `waveform-visualization`, `audio-two-file-comparison` or
`audio-two-file-visual-presentation`.

**The fourth requirement is the exception that proves the rule.** *State no aggregate over a comparison,
by a value or by an absence* looks like comparison content, and it is here because it is a **structural**
rule about any surface that introduces two files at once — including the overview this change's shell
creates. It **specialises** `audio-two-file-comparison` by naming the empty-list case that capability's
own scenario implies but does not spell out; it weakens nothing, and the older requirement stands
untouched.

## 2. The slices

| # | change | observable goal | production scope | ADR | spec delta | manual | depends on |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **R1** | **this change** | five sections exist and one is selected; the selection follows ADR-0026 §5 | composition root: the section value, its reset rule, the shell that hosts a section | **0026** | **new** `inspection-workspace-navigation` | no | — |
| **R2** | `restructure-empty-state` | the pre-inspection surface is the shell's own state, not a section | `RootView`'s empty branch | no | modify `audio-file-inspection` if its wording binds | no | R1 |
| **R3** | `restructure-report-details` | Details holds secondary metadata, warnings and the global status | move out of `ReportView` | no | modify `audio-file-inspection` presentation requirement | no | R1 |
| **R4** | `restructure-report-measurements` | Measurements holds the four measurements, single and paired | move out of `ReportView` | no | modify the measurement capabilities' presentation clauses only if wording binds | no | R1 |
| **R5** | `restructure-waveform-workspace` | the Waveform section, single and paired; **the overlap defect closes here** | `WaveformSection` placement, the 96 pt frame | no | modify `waveform-visualization` presentation requirement | no | R1 |
| **R6** | `restructure-spectrum-workspace` | the Spectrum section, single and paired | `SpectrogramSection` placement | no | modify the spectrogram presentation requirement | no | R1 |
| **R7** | `add-inspection-overview` | Overview as the entry point, ADR-0026 §6 exactly | new section, reusing existing values and the existing envelope | no | **new** requirements in `inspection-workspace-navigation` or its own capability | no | R3, R4, R5 |
| **R8** | `add-comparison-mode-surface` | the five sections in comparison mode; the reduced Comparison Overview | mode switch inside each section | no | modify `audio-two-file-comparison` presentation only; **no semantic change** | no | R7, R6 |
| **R9** | `polish-inspection-workspace` | narrow windows, keyboard, VoiceOver, and the human pass | layout only | no | modify presentation/accessibility clauses | **yes** | all |

**R0** — `extract-exportable-measurements` — is merged and outside this sequence.

**Why R1 is this change rather than the first of nine.** Every other slice needs somewhere to be
delivered into, and R1 is the only one that can be built **without moving any content** — which is also
why it is the one whose behaviour is architecture rather than layout. It is the slice ADR-0026's
promotion conditions are written against, so it closes the architectural question before any layout
depends on it. R2–R9 are created as their own changes once it lands.

**Why R7 is late.** An Overview can only reuse what the other sections have already been given a home
for; building it first would mean inventing values twice.

**Why R8 is isolated.** Comparison mode is the one slice that can silently reintroduce an aggregate, so
it lands after the sections it switches, on its own, with the vocabulary sweep as its gate.

**Why the manual pass is only R9.** ADR-0026's subject is structure, and every claim it makes is a value
a test can read. The question a person must answer is about the finished surface.

## 3. Contract matrix — what may be re-laid-out, and what may not change

| Contract | Protected by | Slice that may touch its presentation | May change | May **not** change |
| --- | --- | --- | --- | --- |
| No aggregate over a comparison | `audio-two-file-comparison` §"State measured facts"; `MeasurementComparison` has no field for one | R8 | where the rows appear | that no count, score, similarity, verdict or **empty differences list** exists |
| Absence is never zero | `audio-two-file-comparison`; ADR-0024 §3 | R4, R8 | wording placement | that a missing value is words, and the side that measured keeps its figure |
| *First* / *second* are positional | ADR-0017; `ComparisonCopy`; `PairedVisualsCopy` | R8 | where the labels sit | the words, and that neither is *original*, *copy*, *source* or *derived* |
| No origin, master, remaster, transcode or upsample | ADR-0024 §8; ADR-0025 §12 | R7, R8 | — | nothing; no surface may state one |
| Measurement outcome semantics | `audio-two-file-comparison`; `MeasurementComparisonPresentationTests` | R4, R8 | layout of the row | `same`/`different`/`incomparable` and their per-metric rules |
| LU difference only where the unit is a difference | ADR-0024 §6 | R4 | where it renders | that only loudness carries one |
| Resolution-aware bandwidth wording | ADR-0023; ADR-0024 §5 | R4 | placement | `indistinguishable`/`separated`, and no hertz difference |
| Waveform absolute amplitude | `waveform-visualization`; `WaveformGeometry.drawnRange` | R5 | the area it is drawn in | no normalisation, per file or per pair |
| Spectrogram absolute energy | ADR-0016; `SpectrogramColourRamp` | R6 | the area | the ramp, the floor, the legend; no auto-contrast |
| Shared axes for a pair | `audio-two-file-visual-presentation`; ADR-0025 §8–§9 | R5, R6, R8 | the space they occupy | `max` extents, the fractions, the two out-of-range sentences |
| Paired stands in for single | `audio-two-file-visual-presentation` | R5, R6, R8 | which section hosts it | that a file is never drawn twice at once |
| Export isolation | `audio-file-inspection`; `ExportComparisonIsolationTests` | none | — | the exported document, byte for byte |
| `schemaVersion` 1 | ADR-0009; `audio-file-inspection` | none | — | anything |
| One PCM read per inspection | ADR-0020, ADR-0021; the decode counters | none | — | the counts; no slice may cause a second read or a recomputation |
| One accessibility element per drawing | `audio-two-file-visual-presentation`; `waveform-visualization` | R5, R6, R9 | the label's surroundings | that a drawing is one element, never one per bucket or cell |
| No zoom, cursor, scrubbing, playback | both visual capabilities | R5, R6 | the area | that a bigger area grants no interaction |
| Report presented in human terms | `audio-file-inspection` §"Present the report in human terms" | R2–R9 | layout | no internal identifiers, no quality judgement, nothing by colour alone, each property one coherent element |

**A redesign may not retire a semantic test by calling it legacy.** Where a slice makes an existing
assertion impossible to write in the same words, that is a finding about the slice.

## 4. The navigation contract R1 must make observable

Ten scenarios, and none of them needs a rendering to assert:

1. a report arrives → the selected section is **Overview**;
2. the reader selects **Waveform** → the selection is Waveform;
3. a comparison is **loading** → still Waveform;
4. a comparison becomes **ready** → still Waveform, and its content is now the paired drawings;
5. the comparison is **closed** → still Waveform, and its content is the single drawing again;
6. another **primary file** is chosen → **Overview**;
7. a new primary file **fails to open** → the section is unchanged and the failed report is presented;
   a failure is not a navigation event;
8. the app **relaunches** → Overview; nothing was persisted;
9. the waveform is **unavailable** → the Waveform section is still reachable and states the absence in
   words; an absent artefact never removes its section;
10. the window is **narrow** → every section is still reachable and its identity is unchanged; layout may
    adapt, the section a reader is in may not.

Scenario 7 is the one ADR-0026 leaves for R1 to pin: a failed inspection produces a report with `.failed`
status, which is still a report about a file the reader chose — so the reader stays where they are, and
only a *successful* new primary returns to Overview. R1 asserts it either way rather than discovering it.

## 5. What this change does not decide

Colour, spacing, type scale, iconography, the SwiftUI types each section is built from, the toolbar's
contents and arrangement, and every word of new copy. Those belong to the slices, and to R9 for the
final pass.

## 6. Deferred, and named so it is not quietly dropped

- **History, recents, a library** — nothing persists, so there is nothing to browse (ADR-0004, ADR-0010).
- **A sidebar** — ADR-0026 §12, and the condition that would reopen it.
- **Interaction on the drawings** — zoom, cursor, scrubbing, synchronised navigation; each needs an
  alignment decision that belongs to evidence comparison.
- **Evidence comparison and Findings** — nothing here authorises either, and the Overview is the most
  tempting place a verdict could appear, which is why ADR-0026 §6 and §8 enumerate rather than gesture.
- **The comparison export** — a document kind of its own (ADR-0017 §9).
- **Closing the VoiceOver traversal gap** — inherited from ADR-0015 and ADR-0017. R9 is where it would
  most naturally be attempted; this change does not require it.
