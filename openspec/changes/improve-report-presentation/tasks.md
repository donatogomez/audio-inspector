# Implementation Tasks

Design only in this step — **no task below is implemented or checked.** Group 1 is the documentary commit
that opens the change; the rest is implementation work on its own branch.

Everything lives in `FeatureAnalysis`, plus `RootView` only if the export placement requires it. No task
touches the domain, the media adapter, the pipeline, the JSON contract, the exporter, drag & drop, the
entitlements or the sandbox model.

Group 2 comes first among the implementation groups because it is the root cause: while the presentation
state is a `String`, the view can only print it.

## 1. OpenSpec contract

- [ ] 1.1 Open the change `improve-report-presentation` with `proposal.md`, `design.md`, the `ADDED`
      delta on `audio-file-inspection`, and this task list. The promoted spec is not edited directly.
- [ ] 1.2 `OPENSPEC_TELEMETRY=0 openspec validate --all --strict` green.

## 2. A typed presentation state

- [ ] 2.1 Replace `PropertyDisplay.state: String` with a closed, exhaustive presentation enum owned by
      `FeatureAnalysis`, decoupled from the domain's `Property` cases and from the wire tokens, mapping
      one-to-one so no distinction is lost.
- [ ] 2.2 Stop rendering a state label for a cleanly measured value, and render the other four states as
      plain words. Remove the `state:` prefix entirely.
- [ ] 2.3 Unit tests: every domain case maps to its distinct presentation state; a measured value carries
      no state label; no presented string contains an underscore or a domain case name.

## 3. Human formatting

- [ ] 3.1 Format byte counts, durations and dates with native format styles.
- [ ] 3.2 Format sample rate and both bitrates at a readable scale, **keeping the exact value as
      secondary detail** so no precision is lost.
- [ ] 3.3 Present channel count as `Mono` for 1 and `Stereo` for 2, and as the bare number above two — the
      domain knows a count, not a layout, so naming any other configuration would infer what was never
      read.
- [ ] 3.4 Unit tests per property, with locale pinned or locale-sensitive fragments avoided, so the suite
      does not depend on the machine's region.

## 4. Comprehensible container and codec

- [ ] 4.1 Present the container through the system's localized description of its type, keeping the
      identifier as secondary detail.
- [ ] 4.2 Present the codec through a small presentation table for the tokens the project produces,
      **falling back to the raw token whenever it is unknown** — never guessing a name.
- [ ] 4.3 Unit tests including the fallback path and an unknown token.

## 5. Warnings and status

- [ ] 5.1 Render warnings from `InspectionWarning.message` and `WarningKind`; translate `field` to the
      property's presentable name and omit the label when there is none, instead of the literal `general`.
      Stable codes leave the primary surface.
- [ ] 5.2 Hide the warnings section entirely when there are none.
- [ ] 5.3 Present the global status as a statement about the inspection — how many properties were read
      and that the rest are simply not defined or not present — never as `completed`/`partial`/`failed`
      and never phrased so it reads as a verdict on the audio. A global failure carries its human message,
      not the error code.
- [ ] 5.4 Unit tests: warning rows carry no code and no wire key; the status text contains no enum name.

## 6. Hierarchy and the export action

- [ ] 6.1 Replace the `Form` + `.formStyle(.grouped)` with a plain scrolling report keeping the same four
      sections and every piece of information currently shown.
- [ ] 6.2 Group the properties into what the file is and how it is encoded, and give the value more
      typographic weight than its label.
- [ ] 6.3 Move `Export JSON…` to a `.toolbar` applied from inside `ReportView`, so `ReportExportModel` and
      its ownership are not touched, and show its transient phase beside the action rather than as a row.
- [ ] 6.4 Confirm no navigation or flow change: the same screen, reorganised.

## 7. Colour, iconography and accessibility

- [ ] 7.1 Constrain colour to inspection state: `uncertain` is not a yellow warning and `unsupported` is
      not an error. Only a genuine failure carries an alerting role, always with text beside it.
- [ ] 7.2 Add at most one semantic symbol distinguishing “not defined by the format” from “could not be
      read”, never an icon tied to a value.
- [ ] 7.3 Make each property row a single accessibility element with a composed label.
- [ ] 7.4 Verify no information depends on colour alone, and check legibility at accessibility text
      sizes.
- [ ] 7.5 Unit tests over the presentation model asserting the accessible label composition, without
      snapshots.

## 8. Existing tests

- [ ] 8.1 Rewrite `ReportPropertyDisplayTests` against the new contract: the eight rows and their order
      are preserved; the assertions on `state`, formatted values, units and details are updated.
- [ ] 8.2 Update the three presentation assertions in `EndToEndFlowTests` to the new literals. The test
      keeps walking the same pipeline and keeps asserting the report is presentable — **no assertion is
      removed or weakened.**
- [ ] 8.3 Confirm the rest of the suite is untouched: export, JSON contract, flow model, dropped source
      and media tests do not reference presentation.

## 9. Manual verification

- [ ] 9.1 Inspect a file and confirm by eye that no underscore code, enum name, wire key, raw UTI or bare
      FourCC appears anywhere on the report.
- [ ] 9.2 VoiceOver pass: each property reads as one coherent element, warnings and status are announced,
      and the export action is reachable in a sensible order.
- [ ] 9.3 Accessibility text sizes: the report stays legible and nothing is clipped.
- [ ] 9.4 Confirm no colour carries meaning on its own.

## 10. Gates and closure

- [ ] 10.1 Four gates green: `./Scripts/check-boundaries.sh`,
      `swift build -Xswiftc -warnings-as-errors`, `swift test`, `openspec validate --all --strict`; plus
      `swiftformat --lint . && swiftlint` and the Xcode app build.
- [ ] 10.2 Confirm the diff touches no domain, media, analysis, `FeatureImport`, exporter, JSON, scheme,
      CI or entitlement file, and adds no dependency.
- [ ] 10.3 Update `CURRENT.md` and archive the change.
