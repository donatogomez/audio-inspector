# add-two-file-measurement-comparison

Compare what two files' **samples** measure — signal levels, true peak, integrated loudness, programme
bandwidth — beneath the technical comparison that already exists. It states four facts side by side and
one difference in LU; it says nothing about where either file came from or which one to keep.

## Manual validation battery

**Prepared before the app is opened**, so a person checking the surface is comparing it against numbers
that already exist rather than deciding on the spot whether what they see is right. Every figure below
came out of the production path — the fixtures are the ones `MeasurementComparisonSurfaceTests` writes,
and the strings are the ones it asserts.

Build each pair as mono 48 kHz float WAV of one second unless the row says otherwise, from
`productionProgramme(to:level:)`. The expectation is what the **Measurements** sub-section must read.

| # | file A | file B | expected row | expected reading |
| --- | --- | --- | --- | --- |
| 2 | comb → 16 kHz, level 0.01 | same comb, level 0.02 | Integrated loudness | `-24.9 LUFS` · `-18.9 LUFS` · Different · **`+6.0 LU`** |
| 2 | " | " | Programme bandwidth | `16.1 kHz` · `16.1 kHz` · Indistinguishable at these resolutions |
| 2 | " | " | Peak sample | `-12.64 dBFS` · `-6.62 dBFS` · Different · **no difference column** |
| 7 | comb → 16 kHz @ **44.1 kHz** | same comb @ **48 kHz** | Integrated loudness | `-24.9 LUFS` · `-24.9 LUFS` · Different · `0.0 LU`, plus the line saying both round to the same figure |
| 8 | comb → 16 kHz @ **88.2 kHz** | same comb @ **96 kHz** | Programme bandwidth | `16.1 kHz` · `16.1 kHz`, resolutions `23 Hz` · `23 Hz`, Indistinguishable at these resolutions |
| 9 | comb → 16 000 Hz | comb → 16 023.4375 Hz | Programme bandwidth | `16.1 kHz` · `16.1 kHz` · **Separated at these resolutions**, plus the line saying they fall in different bins |
| 10 | comb → 16 kHz, 1 s | same comb, **0.1 s** | Integrated loudness | `-24.9 LUFS` · `No value` · *Not comparable — the second file has no value for this.* |
| 10 | " | " | True peak | `-12.21 dBTP` · `-12.21 dBTP` · Same — the absence took nothing with it |
| 6 | comb → 16 kHz, **mono** | same comb, **stereo** | channel note, on three blocks | *Not compared per channel — the files carry 1 and 2 channels…* |
| 6 | " | " | Integrated loudness | `-24.9 LUFS` · `-21.9 LUFS` · Different · `+3.0 LU` |

**What a person is checking that a test cannot.** That the sub-section reads as one thing beneath the
technical rows rather than as a second table; that seven rows and their notes are legible at a narrow
window without truncation; that the difference column does not look like a missing value on the six rows
that have none; and that nothing on screen invites the reader to rank the two files.

**`incomparable(.methodsDiffer)` is deliberately absent from this battery.** Production runs one true
peak method, one bandwidth identity and one loudness algorithm carrying only the two allow-listed
weightings, so **no pair of real files can produce it** — that is measured, in
`MeasurementComparisonProductionReachTests`. It is validated in the presentation tests instead, and a
public setting added only so a screenshot could be taken would be a worse answer than the gap.
