# Implementation Tasks

**Implementation is complete and there is no implementation debt.** Groups 1 to 8 and group 10 are
done; the only open items are the manual accessibility checks in group 7.4 and group 9, which are
**deliberately deferred rather than performed**. The change is archived with them open because
recording them as done would be inventing evidence.

They are a verification debt confined to this surface: no code is waiting on them, and nothing about
them constrains the next slice.

Each contract change updated, in its own commit, the assertions it made obsolete — leaving them broken
until the end would have meant five commits without a safety net.

Everything lives in `FeatureAnalysis`, plus `RootView` only if the export placement requires it. No task
touches the domain, the media adapter, the pipeline, the JSON contract, the exporter, drag & drop, the
entitlements or the sandbox model.

Group 2 comes first among the implementation groups because it is the root cause: while the presentation
state is a `String`, the view can only print it.

## 1. OpenSpec contract

- [x] 1.1 Open the change `improve-report-presentation` with `proposal.md`, `design.md`, the `ADDED`
      delta on `audio-file-inspection`, and this task list. The promoted spec is not edited directly.
- [x] 1.2 `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` green.

## 2. A typed presentation state

- [x] 2.1 Replace `PropertyDisplay.state: String` with a closed, exhaustive presentation enum owned by
      `FeatureAnalysis`, decoupled from the domain's `Property` cases and from the wire tokens, mapping
      one-to-one so no distinction is lost.
- [x] 2.2 Stop rendering a state label for a cleanly measured value, and render the other four states as
      plain words. Remove the `state:` prefix entirely.
- [x] 2.3 Unit tests: every domain case maps to its distinct presentation state; a measured value carries
      no state label; no presented string contains an underscore or a domain case name.

## 3. Human formatting

- [x] 3.1 Format byte counts, durations and dates with native format styles.
- [x] 3.2 Format sample rate and both bitrates at a readable scale, **keeping the exact value as
      secondary detail** so no precision is lost.
- [x] 3.3 Present channel count as `Mono` for 1 and `Stereo` for 2, and as the bare number above two — the
      domain knows a count, not a layout, so naming any other configuration would infer what was never
      read.
- [x] 3.4 Unit tests per property, with locale pinned or locale-sensitive fragments avoided, so the suite
      does not depend on the machine's region.

## 4. Comprehensible container and codec

- [x] 4.1 Present the container through the system's localized description of its type, keeping the
      identifier as secondary detail.
- [x] 4.2 Present the codec through a small presentation table for the tokens the project produces,
      **falling back to the raw token whenever it is unknown** — never guessing a name.
- [x] 4.3 Unit tests including the fallback path and an unknown token.

## 5. Warnings and status

- [x] 5.1 Render warnings from `InspectionWarning.message` and `WarningKind`; translate `field` to the
      property's presentable name and omit the label when there is none, instead of the literal `general`.
      Stable codes leave the primary surface.
- [x] 5.2 Hide the warnings section entirely when there are none.
- [x] 5.3 Present the global status as a statement about the inspection — how many properties were read
      and that the rest are simply not defined or not present — never as `completed`/`partial`/`failed`
      and never phrased so it reads as a verdict on the audio. A global failure carries its human message,
      not the error code.
- [x] 5.4 Unit tests: warning rows carry no code and no wire key; the status text contains no enum name.

## 6. Hierarchy and the export action

- [x] 6.1 Replace the `Form` + `.formStyle(.grouped)` with a plain scrolling report keeping the same four
      sections and every piece of information currently shown.
- [x] 6.2 Group the properties into what the file is and how it is encoded, and give the value more
      typographic weight than its label.
- [x] 6.3 Move `Export JSON…` to a `.toolbar` applied from inside `ReportView`, so `ReportExportModel` and
      its ownership are not touched, and show its transient phase beside the action rather than as a row.
- [x] 6.4 Confirm no navigation or flow change: the same screen, reorganised.

## 7. Colour, iconography and accessibility

- [x] 7.1 Constrain colour to inspection state: `uncertain` is not a yellow warning and `unsupported` is
      not an error. Only a genuine failure carries an alerting role, always with text beside it.
- [x] 7.2 Add at most one semantic symbol distinguishing “not defined by the format” from “could not be
      read”, never an icon tied to a value.
- [x] 7.3 Make each property row a single accessibility element with a composed label.
- [ ] 7.4 Verify no information depends on colour alone, and check legibility at accessibility text
      sizes.
- [x] 7.5 Unit tests over the presentation model asserting the accessible label composition, without
      snapshots.

## 8. Existing tests

- [x] 8.1 Rewrite `ReportPropertyDisplayTests` against the new contract: the eight rows and their order
      are preserved; the assertions on `state`, formatted values, units and details are updated.
- [x] 8.2 Update the three presentation assertions in `EndToEndFlowTests` to the new literals. The test
      keeps walking the same pipeline and keeps asserting the report is presentable — **no assertion is
      removed or weakened.**
- [x] 8.3 Confirm the rest of the suite is untouched: export, JSON contract, flow model, dropped source
      and media tests do not reference presentation.

## 9. Manual verification

**Deliberately deferred, not performed.** These need a person at a keyboard and the suite cannot reach
them, so the change is archived with them open rather than with invented evidence. They are a
**verification** debt, not an implementation one: nothing below is waiting on code.

What is demonstrable by reading the source in the meantime: colour is only ever applied inside the
branch that also renders a text label (`ReportView.swift`), and every symbol has a label beside it
(`symbolsAreLimitedToTheKindsOfAbsenceAndNeverStandAlone`). What cannot be demonstrated that way is how
the surface actually sounds under VoiceOver and looks at accessibility text sizes — which is exactly
what these tasks are for.

- [ ] 9.1 Inspect a file and confirm by eye that no underscore code, enum name, wire key, raw UTI or bare
      FourCC appears anywhere on the report.
- [ ] 9.2 VoiceOver pass: each property reads as one coherent element, warnings and status are announced,
      and the export action is reachable in a sensible order.
- [ ] 9.3 Accessibility text sizes: the report stays legible and nothing is clipped.
- [ ] 9.4 Confirm no colour carries meaning on its own.

## 10. Gates and closure

- [x] 10.1 Four gates green: `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test`, `openspec validate --all --strict`; plus
      the Xcode app build.
- [x] 10.2 Confirmed: the diff touches only `HumanFormat.swift`, `PropertyDisplay.swift` and
      `ReportView.swift` in `FeatureAnalysis`. Domain, media, analysis, `FeatureImport`,
      `AudioInspectorApp`, the exporter, the JSON contract, the scheme, CI and the entitlements are
      byte-identical, and no dependency was added.
- [x] 10.3 Updated `CURRENT.md` and archived the change through `openspec archive`, without editing the
      promoted spec by hand.
