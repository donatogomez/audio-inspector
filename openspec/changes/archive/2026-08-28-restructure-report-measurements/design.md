# Design — the Measurements section

## 1. What the four measurements actually are

Reconstructed from the capabilities and from production, not from memory. **Nothing in this table is
this slice's to change.**

| | Signal levels | True peak | Integrated loudness | Programme bandwidth |
|---|---|---|---|---|
| Domain type | `SignalLevelMetrics` | `TruePeakMeasurement` | `LoudnessMeasurement` | `SignificantBandwidth` |
| Presentation | `SignalLevelMetricsPresentation` | `TruePeakPresentation` | `LoudnessPresentation` | `SignificantBandwidthPresentation` |
| States | loading · metrics · absent · failed | loading · measurement · absent · failed | loading · measurement · absent · failed | loading · measurement (**may carry no reading**) · absent · failed |
| Rows | 4 — Peak sample, RMS level, DC offset, Clipped samples | 1 — True peak | 1 — Integrated loudness | 2 — Programme bandwidth, Analysis resolution |
| Units | dBFS · dBFS · bare 4-dp offset · a count | dBTP | LUFS | kHz/Hz on the grid · resolution in Hz/kHz |
| Rounding | 2 dp, signed, floored at −120 | 2 dp, signed, floored at −120 | **1 dp**, signed, never floored | to the smallest power of ten ≥ the resolution, ≤ 2 dp |
| Per-channel detail | yes, when >1 channel | yes, when >1 channel | **none** — channels combine before the quantity exists | **none** — deliberate; a per-channel list invites a verdict |
| Method sentence | none | `TruePeakCopy.method` — factor and filter | `LoudnessCopy.method` — weighting and gating | `ProgrammeBandwidthCopy.method` — persistence and 60 dB |
| Absence | per row: *"Not computable — this file has no audio frames."* | the same phrase | section sentence: *"Not computable for this file."* | the same sentence, **also** when a measurement carries no reading |
| Capability | `audio-signal-level-metrics` | `audio-signal-level-metrics` | `audio-loudness-measurement` | `audio-significant-bandwidth` |
| ADRs | ADR-0018, ADR-0021 | ADR-0006, ADR-0019 | ADR-0006, ADR-0022 | ADR-0023 |
| Comparison difference | **none** — linear amplitudes, a difference would be a ratio | **none**, same reason | **LU**, and only when the outcome is *different* | **none** — grid overlap; no frequency difference is published |
| What may never be inferred | clipping as a diagnosis, quality | clipping, unsafe, hot, distortion | a target, a platform, normalisation, −23/−14/−16 | a codec, provenance, a cut-off, a verdict against the sample rate |

Two facts from this table decide the whole design:

- **`Clipped samples` has no "not computable" state.** It is always a defined count, including for a
  file with no frames. Absence and zero are different answers here in a way they are nowhere else.
- **Programme bandwidth's "no reading" is not a fourth enum case.** A `.measurement` whose `overall` is
  `nil` reads to a person exactly as an absence, and `ProgrammeBandwidthCopy` already says so in the
  absence's own words. A surface that switched on the enum alone would render an empty measurement.

## 2. The semantic map

Every element the section can render, classified — so what may be reorganised is separated from what
may not be touched.

| Class | Elements | May this slice move it? |
|---|---|---|
| **A · measured value** | the eight figures | position only — never the text |
| **B · unit** | dBFS, dBTP, LUFS, Hz/kHz, the bare offset, the count | **no**: unit travels with its value, in the same string the formatter produced |
| **C · availability / state** | the loading, absent and failed sentences; *not computable* per row | position only — never collapsed, never replaced by a dash |
| **D · method disclosure** | the three method sentences | **may be collapsed** (ADR-0026 §11), never removed |
| **E · resolution / precision limit** | *Analysis resolution*, and the grid-rounding inside the bandwidth value | **no**: stays a visible row of its own, never a `±` |
| **F · comparison value** | both sides of a compared measurement | out of scope — stays on the report page until R8 |
| **G · comparison difference** | loudness in LU, and nowhere else | out of scope — this section publishes none |
| **H · explanatory copy** | per-channel breakdowns, *"Samples at or beyond full scale."*, the absence details | position only |
| **I · editorial judgement** | — | **forbidden, and none exists to move** |

## 3. Three architectures, and the one chosen

### A — four independent panels

What exists today, given a section of its own. **Rejected.** It is the arrangement whose three defects
this slice exists to fix: the grouping stays invisible, nothing aligns across the boxes, and four method
sentences still sit at full weight among the figures. Moving a page into a section without changing it
is not a slice.

### B — one dense measurement table

Every row of all four measurements in a single grid: name, value, detail. **Rejected**, and for a
sharper reason than density. A single table of eight rows has one shape, so it invites one more column
— and the column a reader would want in it is a verdict. `MeasurementComparisonView` already records
this failure mode in the comparison: *"giving those eight rows a column they can never use would invite
someone to fill it."* A flat table also has nowhere to put a method sentence that belongs to three rows
out of eight, and it erases the fact that these are four measurements produced four ways.

### C — a grouped technical reading surface — **chosen**

Two named groups inside one section, one label column running the length of it, each measurement's
figures always visible, and its method sentence behind a disclosure.

|  | A — four panels | B — dense table | C — grouped surface |
|---|---|---|---|
| Scanning speed | slow: eye re-anchors per box | fast, but undifferentiated | fast: one column, four named stops |
| Density | poor — four card frames | highest | high — no card frames, grouped rules |
| Units | kept | kept | kept |
| Absent / failed | one sentence per box | awkward: a sentence in a row of values | one sentence in the measurement's own place |
| Method disclosure | four full sentences at full weight | nowhere to put it | collapsed per measurement, reachable in a click |
| 720 pt | four boxes stack acceptably | columns collide | one label column plus a value stack |
| Accessibility | one element per row | one element per row, weak grouping | one element per row, groups are headings |
| Comparison future-proofing | R8 must undo four boxes | R8 must undo a table shape | R8 adds a surface beside it; nothing to undo |
| Reads as a scorecard | mildly — four cards | **yes** — a table wants a verdict column | no — prose rhythm, no frames, no colour |

**The grouping is the report's own, not this slice's invention.** `ReportView`'s own comments already
order these four by exactly this distinction: the signal levels, the true peak and the loudness are
*"the level sections"*, and the programme bandwidth is *"the first measurement in the report about
frequency rather than level"*. R3 took Details' grouping from `ReportPropertyFormatter.groups(for:)`
rather than inventing one; there is no equivalent function for measurements, so the distinction is
written down here — in the report's own words, **Level** and **Frequency**, and describing a physical
quantity rather than ranking anything.

A group of one is honest. *Frequency* holds one measurement because one of the four is about frequency,
and saying so is the point.

## 4. The information architecture

- **Order: signal levels → true peak → integrated loudness → programme bandwidth.** Exactly the report's
  existing order, which `ReportView` argues for at length. Nothing is reordered by this slice.
- **Groups:** *Level* holds the first three, *Frequency* holds the fourth.
- **Hierarchy:** name in the label column at `.callout`/secondary; value at `.callout`/medium; the
  per-channel or explanatory detail beneath the value at `.caption`/secondary. The measurement's own
  title is a group-internal heading, so a reader can tell which method a row belongs to.
- **Availability** appears where the rows would be — a measurement that is loading, absent or failed
  shows its sentence in its own place, never an empty area and never a dash standing in for a sentence.
- **Detail** — per-channel breakdowns, the clipped-samples explanation, the absence reasons — is always
  visible, beneath the value it qualifies.
- **Method disclosure** is the one thing collapsed, per measurement, behind *"How it was measured"* —
  the phrase the existing accessibility labels already use, so no new vocabulary enters the surface.
- **Always visible, never collapsed:** every value, every unit, every state sentence, every per-channel
  detail, and *Analysis resolution*.
- **Single file is the whole behaviour.** A comparison changes nothing here (§6).

### Why collapsing the method sentences is permitted

ADR-0026 §11 names *"a method line"* first among what may be collapsed, and forbids collapsing *"a
value, its unit, an absence, a failure, a certainty state, or any sentence a capability requires"*.
Read together those two clauses can only mean that **collapsed is not hidden**: the true peak's method
*is* required by `audio-signal-level-metrics`, so if a required sentence could not be collapsed, §11's
first clause would name a case that cannot exist. *"Reachable in a click and never removed"* is the
ADR's own definition, and it is what the capability's *"the method travels with the value"* asks for —
the method stays inside the measurement, one control away, in the same section, and reachable by an
assistive reader.

Nothing else is collapsed. In particular *Analysis resolution* stays a visible row: §11 permits
collapsing *"a resolution"*, and this slice declines the permission, because that row is the one thing
keeping the bandwidth figure from reading as an exact frequency.

## 5. `PropertyDisplay.detail` — R3's deferred 7.1 is **not** R4's

R3 deferred splitting `PropertyDisplay.detail` into the exact figure and the reason, recording that *"it
touches a type R4's surfaces will share"*. **That forecast does not hold, and the debt is not resolved
here.** `PropertyDisplay` is used by `ReportDetailsView`, `ReportView` and the comparison; the four
measurements have their own row types — `SignalLevelMetricsRow`, `TruePeakRow`, `LoudnessRow`,
`ProgrammeBandwidthRow` — and this section touches `PropertyDisplay` nowhere. Splitting it to satisfy a
forecast would be an abstraction with no caller. 7.1 stays deferred, and its real owner is whichever
slice next reworks Details or the comparison surface.

## 6. The comparison, and what this slice does with it — nothing

R3 set the precedent and this slice follows it exactly: **Details does not carry the technical
comparison, even though the comparison's eight rows are Details' own properties**, because the
comparison is one whole surface and R8 owns it.

So: when the reader is on Measurements, the four measurements of the **primary** file are presented, and
no comparison appears — for every comparison state, `none`, `loading`, `ready` and `failed` alike. The
comparison stays intact, unchanged, in the same call with the same presentation, on the report page the
three remaining transitional sections show. It is reachable exactly as the technical comparison has been
reachable since R3.

This is the only reading that does not invent a comparison information architecture, and inventing one
is what R8 exists for. Concretely, this slice publishes **no** comparison value, **no** difference, and
**no** aggregate — direct or by absence.

## 7. The presentation seam

A pure derivation, `MeasurementsDisplay`, turns the four presentations into groups → measurements →
rows. It exists to keep four parallel switches out of the view, and it is bound by what it may not do:

- **Every string comes from the four existing copy owners.** `SignalLevelMetricsCopy`, `TruePeakCopy`,
  `LoudnessCopy` and `ProgrammeBandwidthCopy` are called; none is re-implemented, and no value is
  formatted here. The two group names and the disclosure label are the only new strings, and none of
  them names a magnitude.
- **No domain value is read.** The derivation switches on the presentation enums and hands what it gets
  to the copy owner that owns it.
- **No state.** It is a value produced from its inputs, so it is tested without a view.
- Nothing moves to the domain, nothing is recomputed, and no second comparison model appears.

## 8. Routing

`WorkspaceSection.measurements` gains its own branch of the switch R3 introduced. `Overview`, `Waveform`
and `Spectrum` keep the transitional report page, which is otherwise untouched — including the
comparison it carries and the export in its toolbar. The sections stay five, the selection stays where
R1 put it, and no navigation machinery is introduced.

Because the branches are alternatives, the four measurement blocks on the report page and this section
can never be on screen at once: selecting Measurements replaces the page rather than adding to it.
