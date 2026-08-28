# Give the Measurements section its content

## Why

R1 built the workspace's five sections and the selection that moves between them. R3 gave **Details**
the first content of its own. **Measurements is still the report page**: selecting it shows the same
long scroll every other unfinished section shows, and the four figures it is named for sit near the
bottom of that page as four more boxes in a column of nine.

Three things are wrong where they sit today, and none of them is about the numbers:

- **Four boxes say "four unrelated things".** Signal levels, true peak and integrated loudness are all
  about *level*; programme bandwidth is about *frequency*. `ReportView` already knows this — its own
  comments order the sections by exactly that reasoning — but the surface renders the distinction as
  four identical cards, so the reasoning is invisible to the reader it was made for.
- **Nothing aligns.** Each box lays its labels out independently, so a reader comparing a peak against a
  loudness re-anchors their eye at every box. There are eight rows across the four measurements and no
  column running through them.
- **The four method sentences dominate.** Each measurement carries a sentence saying how it was
  produced — required, and correctly so — and four of them stacked among eight rows of figures make the
  explanations louder than the facts they explain. ADR-0026 §11 exists for exactly this case.

## What changes

Selecting **Measurements** presents the four measurements as one reading surface: two named groups —
*Level* and *Frequency*, the report's own distinction — one label column running the length of the
section, and each measurement's method sentence behind a disclosure that never removes it.

Every figure, unit, state, per-channel breakdown, resolution and sentence is the one the four existing
copy owners already produce. This slice reaches for no domain value, formats nothing, and computes
nothing.

## What does not change

- **No measurement is taken, retaken or recomputed.** No decoder, no PCM read, no accumulator, no DSP.
  The section consumes the presentations the composition root already builds.
- **The comparison is untouched** and stays exactly where R3 left it, on the report page the remaining
  three transitional sections show, until R8 builds the comparison surface. This slice introduces no
  comparison of its own and no aggregate over one.
- **The export, the DTOs and `schemaVersion` 1** are untouched.
- **R1's navigation, R2's pre-inspection surface and R3's Details** are untouched. The five sections
  stay five, and the one rule that moves the reader is unchanged.
- **Nothing is judged.** No score, no grade, no threshold, no target, no colour that varies with a
  value, and no statement about the file's origin, master or codec.
