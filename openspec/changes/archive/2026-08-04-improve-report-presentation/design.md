## Context

`ReportView` is a `Form` with `.formStyle(.grouped)` — the idiom of a Preferences pane — and it forwards
domain and wire vocabulary verbatim. An audit of the current surface found twenty issues: seven
implementation leaks, two formatting defects, seven UX problems, three visual ones, and an accessibility
gap, plus deliberate non-goals.

The architecture is not the problem and does not change. `PropertyDisplay` is already the right seam: a
pure, testable, view-free translation of `TechnicalProperties` into presentable rows. What it produces is
wrong, not that it exists.

Two project rules bound every decision here:

- **Invariant #2 — never invent a value.** Formatting must not fabricate precision or infer facts the
  domain does not carry.
- **Invariant #4 — format ≠ quality.** Nothing presented may suggest that a value is good or bad. This is
  why colour is constrained and why explanatory text is excluded from this change.

## Goals / Non-Goals

**Goals:** no internal token reaches the screen; values are readable; the hierarchy reads as a report;
the export action is separated from content; the surface is usable with VoiceOver and system text sizes.

**Non-Goals:** teaching text, quality judgements, any DSP or visualisation, navigation or flow changes,
and any change to the domain, the pipeline, the JSON contract or the exporter.

## Decisions

### 1. A closed presentation state, replacing the `String`

`PropertyDisplay.state: String` is the root cause of the main leak. It becomes a closed, exhaustive enum
owned by `FeatureAnalysis`, deliberately **decoupled from both** the domain's `Property` cases and the
wire tokens, so that renaming either cannot silently change what a user reads.

It carries the meaning the user needs, not the mechanism:

| Domain case | Presentation state | What the user is told |
| --- | --- | --- |
| `available` | `measured` | the value, with no state label at all |
| `unavailable` | `notPresent` | the file does not carry this |
| `unsupported` | `notDefinedByFormat` | this format does not define it |
| `uncertain` | `readButUnreliable` | read, but not dependable — with the reason |
| `failed` | `couldNotBeRead` | reading it failed |

The mapping stays one-to-one, so no distinction the domain makes is lost. **A cleanly measured value shows
no state label**: today every row carries one, which is what makes the surface feel like a debugger.

### 2. Formatting, per property

Native APIs, no unit library, no invented precision.

| Property | Today | Presented as | Mechanism |
| --- | --- | --- | --- |
| Size | `8421376 bytes` | `8.42 MB` | `ByteCountFormatStyle` (file style) |
| Duration | `372.51 seconds` | `6:12` | `Duration`, seconds → minutes/seconds |
| Sample rate | `44100 hertz` | `44.1 kHz` | derived; exact integer kept as secondary detail |
| Declared / estimated bitrate | `128000 bitsPerSecond` | `128 kbps` | derived from bits per second |
| Channel count | `2` | `2 (Stereo)` | **only** 1 → Mono and 2 → Stereo (see below) |
| Bit depth | `16 bits` | `16-bit` | unchanged in substance |
| Modified date | default `.dateTime` | explicit date + time style | `Date.FormatStyle` |
| Container | raw UTI | localized type name | see §3 |
| Codec | `lpcm` | `Linear PCM` | see §3 |

**Precision is not lost.** Rounding to `44.1 kHz` discards information an archivist needs, so the exact
value stays available as secondary detail, and the JSON — which is untouched — keeps carrying the raw
number. Formatting is a presentation concern layered over the value, never a replacement for it.

**Channels: 1 → Mono, 2 → Stereo, and nothing else.** The domain knows a *count*, not a layout. Naming
`6` as “5.1” would be inferring a layout that was never read — invariant #2. For counts above two, only
the number is shown.

**Locale.** Formatting is locale-sensitive by construction and the package declares `defaultLocalization:
"en"`. Tests must either pin a locale or avoid asserting locale-sensitive fragments, or they will pass on
one machine and fail on another.

### 3. Container and codec

Both are non-localized tokens on purpose — they are the JSON contract's identity — so the translation
belongs entirely to presentation.

- **Container** arrives as a Uniform Type Identifier, and by design (ADR-0012, spike 0031/F) it is
  **always `uncertain`, never `available`**. So today the very first row shows an opaque identifier *and*
  the word `uncertain`. It is presented through the system's own localized description of the type, with
  the identifier retained as secondary detail. Resolving it in `FeatureAnalysis` requires
  `UniformTypeIdentifiers`, which the boundary rules permit (they forbid Media frameworks, Accelerate,
  SwiftData, AppKit and `URL`).
- **Codec** arrives as a FourCC token. A small presentation table names the tokens the project actually
  produces and can name confidently — `lpcm` → `Linear PCM` — and **falls back to the raw token whenever
  it is unknown**. Guessing a name for an unrecognised token would invent information; showing the token
  is the honest fallback.

Both keep the technical token visible as secondary detail rather than discarding it: the archivist needs
the exact identifier, the collector needs the name.

### 4. Warnings

The domain already carries everything needed: `InspectionWarning` has a human `message`, a `kind`
(`unavailable` / `unsupported` / `uncertain` / `failed`) and an optional `field`. The current view ignores
all three and prints `code.rawValue`.

- `message` becomes the primary text.
- `kind` drives grouping and the minimal iconography.
- `field` is translated to the property's presentable name using the same table as the rows; when absent,
  the label is **omitted** rather than replaced with the literal `general`.
- The stable `code` stays out of the primary surface. It remains in the JSON, which is where it is
  contractually meaningful.
- The section is **hidden entirely when there are no warnings**, instead of stating that it has nothing
  to say.

### 5. Status

`completed` / `partial` / `failed` are enum names, and worse, they describe *how the analysis ran*, not
what the file is. A user reading `partial` cannot tell whether the problem is their file or the app.

It is presented as a statement about the inspection, phrased so it cannot be read as a verdict on the
audio: how many properties were read, and that the remainder are simply not defined or not present for
this format. A global `failed` says the file could not be inspected — never *why it is bad* — and carries
its human message, not the error code.

### 6. Structure

The `Form` + `.formStyle(.grouped)` is replaced with a plain scrolling report that keeps the same four
sections — file, properties, warnings, result — and every piece of information currently shown.

- Properties are grouped into what the file **is** (container, codec, duration) and how it is **encoded**
  (sample rate, channels, bit depth, bitrates), so that `Estimated bitrate` — `uncertain` by design,
  always — no longer shouts as loudly as `Duration`.
- The value carries more typographic weight than its label, which is the opposite of a form.
- Navigation and flow do not change: this is the same screen, better organised.

### 7. Export action

`Export JSON…` is a form row today, and its transient phase occupies a permanent row.

`ReportView` receives the export action and owns `ReportExportModel`. Moving the button to `RootView`
would move that ownership, so instead **the action is attached with `.toolbar` from inside `ReportView`**:
SwiftUI attaches it to the window regardless, the ownership does not move, and `ReportExportModel` is not
touched. The transient phase is shown next to the action rather than as a row of the report.

### 8. Colour and iconography

- **Colour communicates inspection state only, never quality.** Specifically: `uncertain` is **not** a
  yellow warning and `unsupported` is **not** an error — both are ordinary outcomes of reading a format,
  and colouring them would tell the user their file is worse, which is invariant #4.
- Only a genuine failure carries an alerting role, and it is always accompanied by text.
- **Iconography is minimal and semantic:** at most a symbol distinguishing *kinds of absence* — “the
  format does not define this” versus “this could not be read” — which are semantically different and
  visually identical today. Never an icon tied to a value.

### 9. Accessibility

- A property row becomes a single accessibility element with a composed label, instead of four loose
  fragments (name, value, `state: …`, detail).
- No information is conveyed by colour alone.
- System text sizes are checked at accessibility sizes, particularly the relationship between a value and
  its secondary detail.
- Reading order is verified after the export action moves to the toolbar.
- VoiceOver behaviour is verified by hand: the automated suite cannot reach it.

## Risks / Trade-offs

- **Formatting can destroy precision.** Mitigated by keeping the exact value as secondary detail and by
  leaving the JSON untouched.
- **Locale-sensitive tests.** Mitigated by pinning or avoiding locale-dependent assertions.
- **“Professional-looking” has no completion criterion.** Mitigated by specifying concrete, checkable
  defects rather than an aesthetic goal.
- **Naming a codec could become a claim.** Mitigated by the fallback rule: unknown tokens are shown as
  tokens, never guessed.
- **Moving focus order** can regress accessibility silently; it is on the manual checklist.
- **The line between naming and judging is thin.** This change permits only strictly nominal labels
  (`Linear PCM`, `Stereo`, `Not supported`) and no sentence that characterises a value. Teaching text is
  deliberately deferred to `add-audio-property-explanations`, which will carry its own normative
  requirement and review.

## Migration Plan

Additive and presentation-local. No stored data, no schema, no public package API and no wire format
changes; a report produced before this change presents identically in substance afterwards.

## Open Questions

None blocking. One decision is deliberately left to implementation with the code in hand: whether the
secondary technical detail (exact sample rate, raw UTI, FourCC token) is always visible or shown only
where it adds value. Either satisfies the requirement; the choice is one of density.
