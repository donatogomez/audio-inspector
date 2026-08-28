# Design — Details, assembled from what the report already says

ADR-0026 decides what Details holds (§10) and what may be collapsed (§11). This document sequences the
work and names what must survive it.

## 1. What the report shows today, and who owns each block

Read from `ReportView`, in render order:

| # | Block | Source | Owner |
| --- | --- | --- | --- |
| 1 | hero header | `ReportPropertyFormatter.summary(for:)` | **R7** Overview |
| 2 | Waveform | `ReportVisuals` | **R5** |
| 3 | Signal levels | `SignalLevelMetricsPresentation` | **R4** |
| 4 | True peak | `TruePeakPresentation` | **R4** |
| 5 | Integrated loudness | `LoudnessPresentation` | **R4** |
| 6 | Programme bandwidth | `SignificantBandwidthPresentation` | **R4** |
| 7 | Spectrogram | `ReportVisuals` | **R6** |
| 8 | **Format** · **Encoding** | `ReportPropertyFormatter.groups(for:)` | **R3** |
| 9 | Comparison | `ComparisonPresentation` | **R8** |
| 10 | **Notes** | `ReportPropertyFormatter.displays(for: warnings)` | **R3** |
| 11 | **Result** | `ReportPropertyFormatter.outcome(for:properties:)` | **R3** |
| 12 | **File** | `report.file` | **R3** |
| — | export action | `ReportExportModel` | see §7 |

R3 owns 8, 10, 11 and 12 — five named blocks, four sources, one report.

## 2. Every fact this slice moves

Nine property rows in two groups, five file facts, the notes, and the outcome. Each row is a
`PropertyDisplay`: a **name**, a **value or `—`**, a **state** (with a label for everything except a
clean measurement, and a symbol for two of them), and a **detail** (the exact figure behind a rounded
value, or the reason an unreliable reading carries).

| Group | Rows |
| --- | --- |
| **Format** | Container · Codec · Duration |
| **Encoding** | Sample rate · Channel count · Bit depth · Declared bitrate · Estimated bitrate · Average file bitrate |
| **File** | Name · Extension · Size (rounded **and** exact) · Modified · Source |
| **Notes** | subject + message + state, per warning; **absent entirely when there are none** |
| **Result** | one sentence, from the status and the rows' states |

**The grouping is not this slice's to invent.** `ReportPropertyFormatter.groups(for:)` already decides
which row belongs to Format and which to Encoding, and it is untouched: this slice renders that decision,
it does not re-make it.

## 3. Three layouts, and the one chosen

| | Shape | Verdict |
| --- | --- | --- |
| **A** | five stacked areas — Format, Encoding, File, Notes, Result | rejected: it is today's page with a different scroll around it, and it keeps all three defects the proposal names |
| **B** | one dense definition list for all nine rows, then File, Notes, Result | rejected: it **erases the Format/Encoding distinction**, which is a decision `groups(for:)` owns and this slice may not overturn |
| **C** | **one technical area with the two groups named inside it**, File beside it, Notes when present, and Result set apart | **chosen** |

**C** keeps the grouping legible as a distinction rather than as two boxes, gives the whole section one
label column so the eye anchors once, and takes Result out of the card rhythm — because it is a
statement about the *reading*, and styling it as a tenth fact is what makes it read as one.

```
┌──────────────────────────────────────────────────────┐
│  Technical                                           │
│  ┌────────────────────────────────────────────────┐  │
│  │ FORMAT                                         │  │
│  │   Container              WAV                   │  │
│  │   Codec                  Linear PCM            │  │
│  │   Duration               3:42                  │  │
│  │                          222.507 s             │  │
│  │ ENCODING                                       │  │
│  │   Sample rate            44.1 kHz              │  │
│  │   Bit depth              —                     │  │
│  │                          Not defined by this…  │  │
│  └────────────────────────────────────────────────┘  │
│  File                                                │
│  ┌────────────────────────────────────────────────┐  │
│  │   Name · Extension · Size · Modified · Source  │  │
│  └────────────────────────────────────────────────┘  │
│  Notes                            (only when present)│
│  ┌────────────────────────────────────────────────┐  │
│  │   subject / message                            │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  Every property was read.        ← Result, no card   │
└──────────────────────────────────────────────────────┘
```

## 4. Progressive disclosure: none, and why

ADR-0026 §11 permits collapsing *"a method line, a resolution, a reason, a limitation"* and forbids
collapsing *"a value, its unit, an absence, a failure, a certainty state"*.

On this surface the only candidate is `PropertyDisplay.detail`, and it is **two different things behind
one field**: the exact figure behind a rounded value, and the reason an unreliable or undefined reading
carries. Collapsing it collapses both, and the second is the half a reader most needs beside the value it
explains. Splitting the field is a change to the presentation model — `PropertyDisplay` is shared with
the surfaces R4 will build — and this slice's remit is to move content, not to re-model it.

So **nothing is collapsed**, and the reason is recorded rather than the disclosure added for its own
sake. It is named as a follow-up.

## 5. Routing: the composition root chooses, as it already does

`WorkspaceSection` lives in `AudioInspectorApp` and `ReportView` lives in `FeatureAnalysis`, which cannot
see it. So the root chooses the surface — the same shape it already uses to join two feature modules that
cannot see each other:

- `.details` → `ReportDetailsView`
- everything else → the existing `ReportView`, unchanged

**No new navigation.** No stack, no split view, no sidebar, no second selection, and no change to R1's
lifecycle: the section state stays exactly where R1 put it.

## 6. What the other four sections show, and why that is not duplication

They show the report page they have shown since R1, whole and unchanged. Details shows the new surface.
They are **alternatives**, never both at once, so the five blocks this slice moves have exactly one
visible owner at any moment. A test refuses the other arrangement.

That is the honest transitional statement: R3 makes one section real, and the four still-unfilled ones
keep the surface that has been standing in for them.

## 7. The comparison and the export during the transition

**The comparison is untouched** — same block, same place, same words, inside the report page the other
four sections show. It does not move into Details, and R8 is where it becomes a mode.

**The export action stays where it is**, in the report page. ADR-0026 §10 says Details eventually holds
*"the export action's context"*, and this slice does not move it: doing so would take it away from four
of the five sections during the transition, which is a larger loss than a reader in Details switching
sections to export. Recorded, not overlooked.

## 8. Responsive and accessibility, for this section only

A reading measure rather than the window's width, so a wide window adds space and not line length. At the
minimum window nothing truncates and nothing scrolls sideways; long values wrap. Each property is one
accessibility element carrying its whole sentence — the rule `PropertyRow` already follows — the groups
carry headings, warnings do not depend on colour, and Result is distinguishable from the facts by
position and wording rather than by colour. The full traversal audit is R9's.

## 9. Deferred

- **Splitting `PropertyDisplay.detail`** into the exact figure and the reason, so the first could be
  collapsed. It touches a type R4's surfaces will share.
- **Moving the export action into Details** (ADR-0026 §10), once the sections it would leave are real.
- **The full accessibility and responsive passes** — R9.
