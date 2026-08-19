import AudioInspectorAnalysis
import AudioInspectorDomain
import Foundation
import Testing

// Two faults the full suite found once the accumulator met every other suite's fixtures. Both were
// real, both are fixed, and neither would be caught by a test about bandwidth: they are about the
// arithmetic surviving inputs `PCMChunk` permits.
//
// `PCMChunk` bounds **samples** — finite, no NaN, no infinity — and says nothing about what a windowed
// transform of them can produce. That gap is where both of these live.

@Suite("Analysis — significant bandwidth survives numeric extremes")
struct SignificantBandwidthNumericExtremeTests {

    private func measure(_ samples: [Float], rate: Double = 48_000) throws -> SignificantBandwidth? {
        var accumulator = try #require(SignificantBandwidthAccumulator(sampleRate: rate, channelCount: 1))
        var start = 0
        while start < samples.count {
            let count = min(4_096, samples.count - start)
            accumulator.accumulate(try PCMChunk(startFrame: start, channels: [Array(samples[start ..< start + count])]))
            start += count
        }
        return accumulator.finish()
    }

    /// **The budget must be subtracted in decibels, never applied by multiplication.**
    ///
    /// `filePeak * 0.001` underflows to zero for a peak near the bottom of `Float`, and `log10(0)` is
    /// −infinity, which traps on the conversion to a stratum index. A programme this quiet is not an
    /// error and the arithmetic must not make it one. Restoring the multiplication makes this test trap
    /// rather than fail, which is the loudest possible failure.
    @Test("an extremely quiet programme is measured or absent, never a trap", arguments: [1e-30, 1e-38, 1e-42, 1e-44])
    func extremelyQuietProgramme(amplitude: Double) throws {
        let frames = 16_384
        let samples = (0 ..< frames).map { Float(Double(amplitude) * sin(2 * Double.pi * 5_000 * Double($0) / 48_000)) }
        let measurement = try measure(samples)
        // Either answer is honest — what must never happen is a trap, or a published value that is not
        // a number.
        if let overall = measurement?.overall {
            #expect(overall.frequency.isFinite, "published a non-finite frequency at amplitude \(amplitude)")
            #expect(overall.resolution.isFinite && overall.resolution > 0)
            #expect(overall.frequency >= 0)
        }
    }

    /// **A finite input can produce a transform that is not a number.**
    ///
    /// A Hann-windowed transform of enormous-but-finite samples overflows `Float`, and the butterflies
    /// then subtract infinities: the magnitudes come back `NaN`. The accumulator's own eligibility rule
    /// already dictates the answer — a window with no positive spectral peak is not an observation — so
    /// a file the transform cannot represent produces an **absence**, which is the semantics this type
    /// already had rather than a new one invented for the case.
    ///
    /// What is asserted here is that it does not **trap**. `Int(floor(…))` on an infinite or `NaN`
    /// double is a runtime failure, and the peak's conversion to decibels is clamped precisely so this
    /// input cannot reach it.
    @Test("an input the transform cannot represent is an absence, not a trap")
    func transformOverflow() throws {
        let frames = 16_384
        let samples = (0 ..< frames).map { $0.isMultiple(of: 2) ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude }
        let measurement = try measure(samples)
        #expect(measurement?.overall == nil, "a file the transform cannot represent produced \(String(describing: measurement?.overall))")
    }

    /// The two extremes in one file, because a file can hold both — and because this is the case that
    /// separates "absent" from "trapped". The overflowing half yields nothing; the quiet half is
    /// ordinary audio, and whatever the method makes of it must be finite.
    @Test("a file holding both extremes still finishes, with a finite answer or none")
    func bothExtremesTogether() throws {
        let half = 8_192
        var samples = (0 ..< half).map { $0.isMultiple(of: 2) ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude }
        samples += (0 ..< half).map { Float(1e-40 * sin(2 * Double.pi * 5_000 * Double($0) / 48_000)) }
        let measurement = try measure(samples)
        if let overall = measurement?.overall {
            #expect(overall.frequency.isFinite)
            #expect(overall.resolution.isFinite && overall.resolution > 0)
        }
    }
}
