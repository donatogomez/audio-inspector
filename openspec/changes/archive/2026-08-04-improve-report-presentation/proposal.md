## Why

The report surface shows the domain's implementation instead of the file's facts. Every property row
prints `state: available` — the name of a `Property` enum case, prefixed with programmer jargon. Warnings
are rendered as `property_unsupported` and their field as `bitDepth`, the JSON keys. The first row a user
reads, *Container*, shows a raw Uniform Type Identifier such as `com.microsoft.waveform-audio`, and
*Codec* shows the FourCC token `lpcm`. Numbers arrive unformatted: `8421376 bytes`, `44100 hertz`,
`372.51 seconds`, and `128000 bitsPerSecond` — where `bitsPerSecond` is not even a unit, it is the JSON
field name used as one.

None of that is a design preference. The stable codes and non-localized tokens exist **for the JSON
contract**, and they are correct there; the defect is that the presentation layer forwards them verbatim
instead of translating them. The honesty invariant was implemented as *showing the enum*, which is not
the same as being honest: it exposes the implementation and leaves the user to decode it.

The result reads as a debug dump inside a Preferences pane, which undersells work that is otherwise
sound: the per-property state model, the declared-versus-estimated split and the domain/wire separation
all survive this change untouched.

## What Changes

**Presentation only. No capability is added and no functional behaviour changes.**

- **Internal vocabulary stops reaching the screen**: enum case names, `rawValue` codes, JSON keys, the
  literal `general`, raw UTIs, and FourCC tokens where a comprehensible name exists.
- **`PropertyDisplay.state` stops being a `String`** and becomes a closed, exhaustive presentation enum,
  decoupled from both the domain cases and the wire tokens. This is the root cause of the leak: while the
  state is a string, the view can do nothing but print it.
- **Values are formatted for humans** with native APIs — sample rate, bitrate, byte counts, duration,
  channels, dates — preserving enough precision and inventing nothing.
- **Container and codec get comprehensible names**, with the technical token kept as secondary detail
  rather than discarded.
- **Warnings use `InspectionWarning.message` and `WarningKind`**, both of which the domain already
  provides; stable codes stop being the primary text.
- **The global status is expressed as a human statement about the inspection**, never as `completed` /
  `partial` / `failed`, and never in a way that reads as a judgement about the audio.
- **The hierarchy stops imitating a Preferences form**, keeping every piece of information and the
  existing sections: file, properties, warnings, result.
- **`Export JSON…` becomes a visually separate action** instead of a form row.
- **Accessibility becomes a stated criterion**: VoiceOver, system text sizes, contrast, reading order,
  and never colour as the sole carrier of meaning.

**Colour communicates inspection state and never quality.** In particular `uncertain` is not rendered as
a yellow warning and `unsupported` does not suggest the file is defective — both are ordinary, expected
outcomes of reading a format.

## Capabilities

### New Capabilities

None. This corrects how an existing capability is presented.

### Modified Capabilities

- `audio-file-inspection`: adds a requirement fixing what the presented report may and may not contain —
  no internal tokens, human-readable values, and no interpretation of quality. The existing requirements
  about selection, reading, property states, the report structure, the safe origin and the JSON contract
  are **unchanged**.

## Impact

- **Affected specs:** `audio-file-inspection` (one `ADDED` requirement).
- **Affected code:** `FeatureAnalysis` only — `PropertyDisplay`, `ReportPropertyFormatter`, `ReportView`.
  `RootView` only if the export action's placement requires it.
- **Affected tests:** `ReportPropertyDisplayTests` is rewritten against the new contract, and three
  presentation assertions in `EndToEndFlowTests` are updated to the new literals. The end-to-end test
  keeps walking the same pipeline and keeps asserting the report is presentable; **no assertion is
  removed or weakened.**
- **Explicitly unchanged:** `AudioInspectorDomain`, `AudioInspectorMedia`, `AudioInspectorAnalysis`,
  `FeatureImport`, the inspection pipeline, drag & drop, `ReportExportModel` and the export mechanics,
  the `schemaVersion` 1 contract and its exporter, the entitlements and the sandbox model. No new
  dependency.

**Out of scope:** teaching text explaining what each property means — that is `add-audio-property-explanations`,
deliberately separate because it adds new content that could cross the line between describing and judging
quality. Also out: any quality judgement, waveform, spectrogram, DSP, FFT, timeline, playback, comparison,
persistence, and any navigation or flow redesign.
