import Foundation

import AudioInspectorDomain

/// Folds decoded PCM into the programme's **integrated loudness**, in LUFS, following
/// ITU-R BS.1770-5 Annex 1.
///
/// ## Every constant is published, and none of it is a setting
///
/// The two K-weighting stages, the 400 ms block, the 75 % overlap, the −70 LKFS absolute gate, the 10 LU
/// relative offset and the −0.691 conversion offset all come from **ITU-R BS.1770-5 (11/2023), Annex 1**,
/// section by section in `docs/spikes/2026-08-18-loudness-measurement-validation.md` Part A. EBU R 128
/// contributes the *name* LUFS (equivalent to BS.1770's LKFS) and no constant of its own, so nothing here
/// is attributed to it. None of these is reachable from a feature or the app: a gate a user could retune
/// would make the same file read differently across runs, which this project's reproducibility principle
/// rules out (ADR-0006's pattern for engine-versioned constants).
///
/// ## 48 kHz only, and mono or stereo only — by construction, not by a runtime check
///
/// BS.1770-5 publishes filter coefficients **for 48 kHz alone** and asks other rates merely to *match
/// that frequency response*, without publishing a prototype, a per-rate table or a transform. Deriving
/// coefficients for another rate is therefore this project's own work and its own claim, and it belongs
/// to a later task (ADR-0022 §3). Until then this type **refuses** any other rate rather than measuring
/// it with the wrong filter.
///
/// Channels are refused past two for a different reason: BS.1770-5 Table 3 weights a channel by its
/// **position**, never by its index, and Annex 3 generalises that to azimuth and elevation. One channel
/// is safe because it can only be L, C or R and all three weigh 1.0; two are safe because the only
/// two-channel BS.2051 configuration weighs both 1.00 and contains no LFE. **Three is where it breaks**
/// — L/C/R would all weigh 1.0, but the file could equally carry an LFE, which the standard excludes
/// from the measurement entirely, and getting that wrong moves the result by more than the ±0.1 LU the
/// standards themselves tolerate (ADR-0022 §4).
///
/// Both refusals are the failable initialiser, which is the convention `TruePeakAccumulator` and
/// `SignalLevelMetricsAccumulator` already use for a stream they cannot fold.
///
/// ## Not yet the domain's shape
///
/// `finish()` returns a bare `Double?` of LUFS because `LoudnessMeasurement` does not exist yet — it is
/// task group 3, and building it here to give this method a nicer return type would be inventing the
/// domain model from the accumulator's convenience rather than from the domain's needs. For the same
/// reason **nothing in this file is `public`**: the shape that crosses the module boundary is the domain
/// type's, and committing to this one first would mean changing a published signature later. Group 3
/// wraps the scalar; group 7 wires it.
///
/// ## One pass, no samples retained, memory in blocks rather than in frames
///
/// 75 % overlap makes every 400 ms block exactly **four consecutive 100 ms sub-blocks**, so a block's
/// energy is the sum of the last four sub-block energies and **no audio is buffered at all** — a ring of
/// four sums per channel replaces a 400 ms window. What does grow is one `Double` per completed block,
/// ten per second, and that is unavoidable: the relative gate is derived from the whole programme, so
/// whether a block survives cannot be decided when the block is produced. An exact O(1) integrated
/// loudness does not exist (spike B9).
///
/// ## Not `Sendable`, deliberately
///
/// It owns mutable per-channel filter state with no synchronisation. Exactly like its three siblings, it
/// is created and consumed inside one `nonisolated async` operation, never stored on a `Sendable` type,
/// never cached, never shared.
struct LoudnessAccumulator {

    // MARK: - Published constants (ITU-R BS.1770-5, Annex 1)

    /// The only rate whose coefficients the Recommendation publishes.
    static let supportedSampleRate = 48_000.0

    /// Gating block duration, *T*<sub>g</sub>. BS.1770-5 Annex 1, after eq. (2): 400 ms, to the nearest
    /// sample.
    static let blockDuration = 0.400

    /// Overlap between consecutive gating blocks. BS.1770-5 Annex 1: **shall be** 75 %.
    static let blockOverlap = 0.75

    /// Absolute gate Γ<sub>a</sub>, BS.1770-5 Annex 1 eq. (6), in LKFS.
    static let absoluteGate = -70.0

    /// How far below the absolutely-gated loudness the relative gate sits, in LU. BS.1770-5 eq. (6).
    /// **Not** EBU Tech 3342's −20 LU, which belongs to loudness range and is a different quantity.
    static let relativeGateOffset = 10.0

    /// The offset in BS.1770-5 eq. (2). Its NOTE 1 states that it cancels the K-weighting gain at 997 Hz.
    static let loudnessOffset = -0.691

    /// Channel weight *G*<sub>i</sub>, BS.1770-5 Annex 1 Table 3. L, R and C all weigh 1.0, and every
    /// configuration this type accepts is drawn from those three.
    static let channelWeight = 1.0

    // MARK: - Derived sizes

    /// Frames in one gating block. Derived from the published duration and the rate rather than written
    /// as a second number that could drift from it.
    let blockFrames: Int
    /// Frames in one hop — and, because the overlap is 75 %, in one sub-block.
    let hopFrames: Int
    /// Sub-blocks that make up a block: `1 / (1 − overlap)` = 4.
    let subBlocksPerBlock: Int

    private let channelCount: Int

    // MARK: - Mutable state, all confined to one operation

    /// Both sections' delay elements for every channel, carried across chunks: two per section, in
    /// transposed direct form II, laid out flat as `channel * KWeighting.stateCount + index`.
    ///
    /// Flat rather than an array per channel so the hot loop takes one buffer pointer for the whole
    /// state instead of copying a nested array per chunk per channel — that copy triggered
    /// copy-on-write on every call, which is an allocation in the middle of the only loop that matters.
    private var filterState: [Double]
    /// Sum of squares of the K-weighted samples in the sub-block currently being filled, per channel.
    private var partialSubBlockEnergy: [Double]
    /// Frames already folded into that sub-block. Shared by every channel, because a chunk carries the
    /// same frame span for all of them.
    private var subBlockFill = 0
    /// The last `subBlocksPerBlock` completed sub-block sums, per channel, as a ring.
    private var subBlockRing: [[Double]]
    private var ringHead = 0
    /// How many sub-blocks have completed. A block ends with every completion from the fourth onwards.
    private var completedSubBlocks = 0

    /// One value per completed gating block: Σ<sub>i</sub> *G*<sub>i</sub> · *z*<sub>ij</sub>, the
    /// channel-weighted mean square that BS.1770-5 eq. (4) takes the logarithm of.
    private(set) var blockEnergies: [Double] = []

    // MARK: - Construction

    /// Fails on any stream this type cannot measure honestly: a rate other than 48 kHz, a channel count
    /// outside mono/stereo, or a rate whose block does not divide into whole sub-blocks.
    init?(sampleRate: Double, channelCount: Int) {
        guard sampleRate == Self.supportedSampleRate else { return nil }
        guard channelCount >= 1, channelCount <= 2 else { return nil }

        let blocks = Int((Self.blockDuration * sampleRate).rounded())
        let hop = Int((Self.blockDuration * (1 - Self.blockOverlap) * sampleRate).rounded())
        let perBlock = Int((1 / (1 - Self.blockOverlap)).rounded())
        // The sub-block decomposition below is only valid when the block divides exactly. It does at
        // 48 kHz (19 200 = 4 × 4 800); the guard is here so a future rate cannot inherit the shortcut
        // silently.
        guard hop > 0, blocks == perBlock * hop else { return nil }

        self.channelCount = channelCount
        blockFrames = blocks
        hopFrames = hop
        subBlocksPerBlock = perBlock
        filterState = [Double](repeating: 0, count: channelCount * KWeighting.stateCount)
        partialSubBlockEnergy = [Double](repeating: 0, count: channelCount)
        subBlockRing = Array(repeating: [Double](repeating: 0, count: perBlock), count: channelCount)
    }

    // MARK: - Folding

    /// Folds one chunk into the running filter state and block energies.
    ///
    /// A chunk whose channel count disagrees with this accumulator's is ignored, mirroring the guard both
    /// sibling accumulators already use.
    ///
    /// **Independent of chunk size, bit for bit.** Three things could break that and none does: the
    /// filter state crosses chunk boundaries rather than restarting; the recurrence is evaluated one
    /// sample at a time in index order, so no grouping of the work can change its rounding; and the
    /// energy is accumulated **into the running total** rather than as a per-piece partial sum added
    /// afterwards. The last point is the subtle one — a vectorised reduction over a piece would group its
    /// additions by that piece's length, so the same sub-block split differently would round differently.
    ///
    /// This is why `vDSP_biquadD` is **not** used here despite being the obvious primitive, and the
    /// reason is measured rather than assumed: it produced results that differed in the last two or three
    /// digits across chunk sizes (−23.385524041147569 at one frame per chunk against
    /// −23.385524041147661 whole-file), because how it groups an IIR's work depends on the length it is
    /// handed. The difference is far below any tolerance that matters, and it is still the wrong
    /// trade — this project's other analyses are chunk-independent *exactly*, and a loudness figure that
    /// changed with the decoder's buffer size would be a reproducibility defect however small.
    mutating func accumulate(_ chunk: PCMChunk) {
        guard chunk.channelCount == channelCount else { return }
        let frames = chunk.frameCount
        guard frames > 0 else { return }

        var offset = 0
        while offset < frames {
            // Never cross a sub-block boundary inside one pass: the boundary is absolute in the file,
            // not relative to the chunk.
            let take = min(hopFrames - subBlockFill, frames - offset)
            weightAndAccumulate(chunk, from: offset, count: take)
            subBlockFill += take
            offset += take
            if subBlockFill == hopFrames { completeSubBlock() }
        }
    }

    /// The programme's integrated loudness in LUFS, or `nil` when the standard defines none.
    ///
    /// Three situations produce `nil`, and **none of them produces a number**: a programme shorter than
    /// one block, which forms no gating block at all; a programme every one of whose blocks falls below
    /// the absolute gate, digital silence being the clearest case; and the same after the relative gate.
    /// BS.1770-5 eq. (7) divides by the size of the gated set, so an empty set leaves the quantity
    /// undefined — **−70 is the gate, never a result**, and the reference implementation's −70.000 floor
    /// is a display convention this type does not copy (ADR-0022 §6).
    ///
    /// Non-`mutating`: an incomplete trailing sub-block is discarded by simply never being pushed. There
    /// is no flush, no zero-padding and no fabricated final block, which is what BS.1770-5 requires of an
    /// incomplete gating block at the end of the measurement interval.
    func finish() -> Double? {
        guard !blockEnergies.isEmpty else { return nil }
        guard let threshold = relativeThreshold() else { return nil }

        // Pass 2 — eq. (7) keeps **both** conditions. The relative threshold is not necessarily above
        // the absolute one: for a very quiet programme the absolute gate is the binding constraint.
        let gated = blockEnergies.filter {
            let loudness = Self.loudness(of: $0)
            return loudness > threshold && loudness > Self.absoluteGate
        }
        guard !gated.isEmpty else { return nil }

        return Self.loudness(of: Self.mean(of: gated))
    }

    /// The relative threshold Γ<sub>r</sub> this programme derives — BS.1770-5 eq. (6): the loudness of
    /// the absolutely-gated blocks, minus 10 LU. `nil` when no block clears the absolute gate.
    ///
    /// **This is the only place the absolute gate is observable**, and it is exposed for that reason. A
    /// negative control found the gap: disabling the absolute gate entirely left Tech 3341 tests 3 and 4
    /// reading exactly the same values, because the relative gate happened to exclude the same blocks by
    /// itself. What *does* change is the threshold — the −72 dBFS passages drag the intermediate mean
    /// down by about a loudness unit before the subtraction. FFmpeg reports the same quantity, so the
    /// two implementations can be compared at an intermediate rather than only at the answer.
    ///
    /// Derived from the mean of **energies**, converted afterwards. Averaging the blocks' LUFS values
    /// would be averaging logarithms, which is a different quantity.
    func relativeThreshold() -> Double? {
        let aboveAbsolute = blockEnergies.filter { Self.loudness(of: $0) > Self.absoluteGate }
        guard !aboveAbsolute.isEmpty else { return nil }
        return Self.loudness(of: Self.mean(of: aboveAbsolute)) - Self.relativeGateOffset
    }
}

// MARK: - The arithmetic of BS.1770-5 Annex 1

extension LoudnessAccumulator {
    /// BS.1770-5 eq. (2)/(4): −0.691 + 10·log₁₀(Σ *G*<sub>i</sub> · *z*<sub>i</sub>).
    ///
    /// A zero energy gives `-infinity`, which is exactly what the gates should see: `-infinity > -70` is
    /// false, so a silent block excludes itself without a special case.
    static func loudness(of weightedEnergy: Double) -> Double {
        loudnessOffset + 10 * log10(weightedEnergy)
    }

    static func mean(of values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

}

// MARK: - Blocking

private extension LoudnessAccumulator {
    /// Pushes the filled sub-block into the ring and, once four have accumulated, emits the block that
    /// ends with it.
    ///
    /// A block is the sum of the last four sub-blocks, so no window of audio is kept: the identity
    /// `block[j] = Σ of sub-blocks 4j′ … 4j′+3` holds because the hop *is* the sub-block, and 400 ms is
    /// exactly four hops.
    mutating func completeSubBlock() {
        for channel in 0 ..< channelCount {
            subBlockRing[channel][ringHead] = partialSubBlockEnergy[channel]
            partialSubBlockEnergy[channel] = 0
        }
        ringHead = (ringHead + 1) % subBlocksPerBlock
        subBlockFill = 0
        completedSubBlocks += 1

        guard completedSubBlocks >= subBlocksPerBlock else { return }

        // Σᵢ Gᵢ · zᵢⱼ, where zᵢⱼ is the channel's mean square over the whole block.
        var weightedEnergy = 0.0
        for channel in 0 ..< channelCount {
            let blockSumOfSquares = subBlockRing[channel].reduce(0, +)
            weightedEnergy += Self.channelWeight * (blockSumOfSquares / Double(blockFrames))
        }
        blockEnergies.append(weightedEnergy)
    }

    /// Runs `count` frames through both K-weighting stages and adds their squares to each channel's
    /// partial sub-block energy — **one pass per channel, and no intermediate buffer at all**.
    ///
    /// Fusing the filter with the reduction is not only a saving: it removes the only per-chunk
    /// allocation this type would otherwise need, so nothing is retained past the call that offered it
    /// beyond four `Double`s of filter state per channel.
    /// **The two channels are advanced together rather than one after the other**, and the reason is
    /// measured. A biquad is a serial recurrence: each output waits on the two before it, so a single
    /// channel's loop is latency-bound and leaves the processor idle. Two channels are two *independent*
    /// chains, and interleaving them lets both be in flight at once — **0.281 s against 0.455 s** over
    /// ten minutes of stereo in Release.
    ///
    /// The arithmetic per channel is untouched, so the result is bit-identical to the sequential form;
    /// only the order the two channels' instructions issue in changes. `channelCount` is 1 or 2 by
    /// construction, so these two branches are the whole of it.
    mutating func weightAndAccumulate(_ chunk: PCMChunk, from offset: Int, count: Int) {
        guard count > 0 else { return }
        filterState.withUnsafeMutableBufferPointer { state in
            partialSubBlockEnergy.withUnsafeMutableBufferPointer { energies in
                guard let stateBase = state.baseAddress, let energyBase = energies.baseAddress else {
                    return
                }
                guard channelCount == 2 else {
                    chunk.channels[0].withUnsafeBufferPointer { input in
                        guard let base = input.baseAddress else { return }
                        var energy = energyBase[0]
                        for index in 0 ..< count {
                            let weighted = KWeighting.apply(Double(base[offset + index]), state: stateBase)
                            energy += weighted * weighted
                        }
                        energyBase[0] = energy
                    }
                    return
                }
                chunk.channels[0].withUnsafeBufferPointer { first in
                    chunk.channels[1].withUnsafeBufferPointer { second in
                        guard let firstBase = first.baseAddress,
                              let secondBase = second.baseAddress else { return }
                        let firstDelays = stateBase
                        let secondDelays = stateBase + KWeighting.stateCount
                        var firstEnergy = energyBase[0]
                        var secondEnergy = energyBase[1]
                        for index in 0 ..< count {
                            let one = KWeighting.apply(
                                Double(firstBase[offset + index]), state: firstDelays
                            )
                            let two = KWeighting.apply(
                                Double(secondBase[offset + index]), state: secondDelays
                            )
                            firstEnergy += one * one
                            secondEnergy += two * two
                        }
                        energyBase[0] = firstEnergy
                        energyBase[1] = secondEnergy
                    }
                }
            }
        }
    }
}
