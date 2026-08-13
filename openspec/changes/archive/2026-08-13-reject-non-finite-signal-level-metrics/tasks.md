# Implementation Tasks

## 1. Reproduce before designing

- [x] 1.1 Reproduce the defect from **finite** samples and identify the mechanism by measurement rather
      than by reading: which magnitude triggers it, which operation produces the first non-finite value,
      which fields are affected, and whether it depends on chunk size. A temporary probe answered all
      four and was deleted.
- [x] 1.2 Classify it. **Not** an unavoidable overflow for a valid finite input, and **not** a result
      outside what `Float` can represent: `|mean| ≤ max|x|` and `RMS ≤ max|x|`, both finite. It is an
      implementation defect — the partial sums were formed in `Float32` — which decides the fix: repair
      the calculation, do not declare a failure and do not clamp.

## 2. The calculation

- [x] 2.1 Widen each chunk to `Double` before reducing it, reusing a scratch buffer so the widening
      costs no allocation per chunk and memory stays a function of the caller's buffer rather than of
      the file's duration.
- [x] 2.2 Measure the cost against the pre-fix implementation on the same machine: 10 min stereo,
      **0.043 s → 0.064 s Release** and **1.244 s → 1.270 s Debug**. A fast path keeping `Float` for
      ordinary audio was considered and **rejected**: it would make the numeric path depend on the
      input's magnitude, and the `Double` reduction is also the more accurate one.
- [x] 2.3 Confirm chunk independence still holds, at the extremes too, within the tolerance this
      capability already documents — not a widened one.

## 3. The model

- [x] 3.1 Make `SignalLevelMetrics.Channel` and `SignalLevelMetrics` failable, refusing non-finite
      values, a negative peak, a negative RMS, an empty channel list and both directions of the
      `nil`-iff-no-samples rule. Values beyond full scale stay accepted.
- [x] 3.2 Make `finish()` optional, like `SpectrogramAccumulator`'s and `TruePeakAccumulator`'s, so an
      impossible result becomes the existing `failed` outcome rather than a new state.

## 4. Tests

- [x] 4.1 Every field stays finite at every magnitude a `Float` can hold, for constant and
      alternating-sign signals — and the values are asserted to be **correct**, not merely finite, which
      is what distinguishes a fix from a clamp.
- [x] 4.2 The peak and the clipped count are unaffected, as they always were.
- [x] 4.3 Chunk independence at extreme magnitudes, at six chunk sizes and whole-file.
- [x] 4.4 The model refuses `NaN`, `signalingNaN`, `±infinity`, a negative peak and a negative RMS, and
      still accepts values beyond full scale, silence and zero frames.
- [x] 4.5 End-to-end through the real shared read: extreme audio yields an `available` measurement whose
      every field is finite, the exported document carries real numbers, and the neighbouring analyses
      settle exactly as they would have.
- [x] 4.6 Four negative controls, each reverted in full: the model accepting non-finite values again,
      the pre-fix reduction restored, a non-finite result substituted with `0`, and the aggregate guard
      removed so the export could receive one.

## 5. Gates and closure

- [x] 5.1 Four gates green plus the Xcode build and `git diff --check`. Run on the branch head before
      publishing and again on `main` after the merge; the pre-existing flow-state flake did not appear in
      either.
- [x] 5.2 Update `CURRENT.md` and archive through `openspec archive` **after merge**. The delta's
      modified requirement was corrected first: it restated the requirement without three scenarios it
      never intended to touch (silence, chunk independence, non-interference), and `MODIFIED` replaces a
      requirement wholesale, so archiving as written would have deleted three live, tested guarantees.
