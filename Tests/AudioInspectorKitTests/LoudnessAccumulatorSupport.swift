import Foundation
import Testing

@testable import AudioInspectorAnalysis
import AudioInspectorDomain

// Feeding a `LoudnessTestVector` into the production accumulator.
//
// The samples come from the vector's own signal, the same pure function the fixture writer uses, so a
// test here measures exactly what a written file would contain without paying for the file. Nothing
// about the expected value is computed on this side: the targets are the published ones.

enum LoudnessAccumulatorHarness {

    /// Feeds `vector` through a fresh accumulator in chunks of `chunkFrames`, or whole when `nil`.
    /// Returns the accumulator's own answer — `nil` meaning the standard defines none.
    static func measure(
        _ vector: LoudnessTestVector, chunkFrames: Int? = 4_096
    ) throws -> LoudnessMeasurement? {
        var accumulator = try #require(
            LoudnessAccumulator(sampleRate: vector.sampleRate, channelCount: Int(vector.channels))
        )
        try feed(vector, into: &accumulator, chunkFrames: chunkFrames)
        return accumulator.finish()
    }

    /// The LUFS value alone, for the assertions that are about the number rather than the model. The
    /// model's own semantics are covered by "Domain — integrated loudness measurement".
    static func measureLoudness(
        _ vector: LoudnessTestVector, chunkFrames: Int? = 4_096
    ) throws -> Double? {
        try measure(vector, chunkFrames: chunkFrames)?.integratedLoudness
    }

    /// Feeds a vector's frames into an existing accumulator.
    ///
    /// The whole signal is materialised once and then sliced, rather than regenerated per chunk: the
    /// chunk-independence matrix feeds the same vector seven times, and a hundred seconds of stereo is
    /// 9.6 M samples. The samples come from `AudioFixtureSignal.samples(channel:from:count:sampleRate:)`,
    /// which that type's own suite proves equal to its per-sample function.
    static func feed(
        _ vector: LoudnessTestVector, into accumulator: inout LoudnessAccumulator, chunkFrames: Int?
    ) throws {
        let frames = vector.totalFrames
        let channels = Int(vector.channels)
        let planes = (0 ..< channels).map {
            vector.signal.samples(channel: $0, from: 0, count: frames, sampleRate: vector.sampleRate)
        }
        try feed(planes: planes, chunkFrames: chunkFrames, into: &accumulator)
    }

    /// Feeds ready-made planar samples, so a caller that already holds them pays for them once.
    static func feed(
        planes: [[Float]], chunkFrames: Int?, into accumulator: inout LoudnessAccumulator
    ) throws {
        let frames = planes.first?.count ?? 0
        let size = chunkFrames ?? max(frames, 1)
        var start = 0
        while start < frames {
            let count = min(size, frames - start)
            let slice = planes.map { Array($0[start ..< (start + count)]) }
            accumulator.accumulate(try PCMChunk(startFrame: start, channels: slice))
            start += count
        }
    }

    /// Feeds an arbitrary sample function, so a test can build a signal the vector catalogue has no
    /// reason to carry — samples above full scale, for instance.
    static func feed(
        frames: Int,
        channels: Int,
        chunkFrames: Int?,
        into accumulator: inout LoudnessAccumulator,
        sample: (Int, Int) -> Float
    ) throws {
        let size = chunkFrames ?? max(frames, 1)
        var start = 0
        while start < frames {
            let count = min(size, frames - start)
            let planes = (0 ..< channels).map { channel in
                (0 ..< count).map { sample(channel, start + $0) }
            }
            accumulator.accumulate(try PCMChunk(startFrame: start, channels: planes))
            start += count
        }
    }

    /// A steady stereo 1 kHz tone at 48 kHz, described the way the vectors are, for tests that need a
    /// shape the published catalogue does not carry.
    static func tone(
        dBFS: Double?, seconds: Double, channels: UInt32 = 2, frequency: Double = 1_000
    ) -> LoudnessTestVector {
        LoudnessTestVector(
            name: "harness-\(dBFS.map { String($0) } ?? "silence")-\(seconds)s",
            authority: .derived(rationale: "a shape built inside a test, never compliance evidence"),
            sampleRate: 48_000,
            channels: channels,
            frequency: frequency,
            segments: [LoudnessSegmentSpec(dBFS: dBFS, seconds: seconds)],
            expectation: .notComputable(oracleFloor: -70.0),
            discriminates: "nothing — a harness shape"
        )
    }

    /// The same described signal at another sample rate.
    ///
    /// Relabelled `derived`, because the publisher's table does not contain it: EBU Tech 3341's signals
    /// are published synthesised at 48 kHz, and a resynthesis elsewhere is a **derived acceptance case**
    /// rather than an official vector. The expected reading is unchanged, because the signal the
    /// description names is the same signal.
    static func resynthesised(_ vector: LoudnessTestVector, at rate: Double) -> LoudnessTestVector {
        var copy = vector
        copy.sampleRate = rate
        copy.name = "\(vector.name)-at-\(Int(rate))"
        copy.authority = .derived(
            rationale: "the same described signal, resynthesised at \(Int(rate)) Hz"
        )
        return copy
    }

    /// A multi-level tone, for a gating shape short enough to feed one frame at a time.
    static func segments(_ specs: [(dBFS: Double?, seconds: Double)]) -> LoudnessTestVector {
        LoudnessTestVector(
            name: "harness-segments",
            authority: .derived(rationale: "a shape built inside a test, never compliance evidence"),
            sampleRate: 48_000,
            channels: 2,
            frequency: 1_000,
            segments: specs.map { LoudnessSegmentSpec(dBFS: $0.dBFS, seconds: $0.seconds) },
            expectation: .notComputable(oracleFloor: -70.0),
            discriminates: "nothing — a harness shape"
        )
    }
}
