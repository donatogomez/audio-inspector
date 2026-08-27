import CoreGraphics
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// Group 4's subject: **two envelopes laid out against one time axis, as arithmetic.**
//
// Nothing here renders. What is asserted is the shared extent, each side's share of it, that the share
// is handed to the *existing* bucket arithmetic rather than replacing it, and that laying two files out
// together changes neither file's data.

@Suite("Feature — two waveforms on one time axis")
struct PairedWaveformAxisTests {

    // MARK: - Fixtures

    private func stream(rate: Double, seconds: Double) -> PCMStreamDescription {
        PCMStreamDescription(sampleRate: rate, channelCount: 2, frameCount: Int(rate * seconds))!
    }

    private func stream(rate: Double, frames: Int) -> PCMStreamDescription {
        PCMStreamDescription(sampleRate: rate, channelCount: 2, frameCount: frames)!
    }

    private func envelope(peaks: [Float], frameCount: Int = 44_100) -> WaveformEnvelope {
        WaveformEnvelope(
            buckets: peaks.map { WaveformBucket(minimum: -$0, maximum: $0)! },
            frameCount: frameCount,
            channelCount: 2
        )!
    }

    private let total = CGSize(width: 800, height: 100)

    // MARK: - The shared extent

    @Test("two files of the same duration each take the whole axis")
    func equalDurations() {
        let axis = PairedWaveformAxis(
            first: stream(rate: 44_100, seconds: 3), second: stream(rate: 44_100, seconds: 3)
        )
        #expect(axis?.sharedSeconds == 3)
        #expect(axis?.first?.fraction == 1)
        #expect(axis?.second?.fraction == 1)
        #expect(axis?.first?.remainderFraction == 0)
        #expect(axis?.second?.remainderFraction == 0)
    }

    @Test("a first file half as long takes half the axis, and the second takes all of it")
    func firstIsShorter() {
        let axis = PairedWaveformAxis(
            first: stream(rate: 44_100, seconds: 5), second: stream(rate: 44_100, seconds: 10)
        )
        #expect(axis?.sharedSeconds == 10)
        #expect(axis?.first?.fraction == 0.5)
        #expect(axis?.second?.fraction == 1)
        #expect(axis?.first?.remainderFraction == 0.5)
    }

    @Test("a second file half as long takes half the axis, and the first takes all of it")
    func secondIsShorter() {
        let axis = PairedWaveformAxis(
            first: stream(rate: 44_100, seconds: 10), second: stream(rate: 44_100, seconds: 5)
        )
        #expect(axis?.sharedSeconds == 10)
        #expect(axis?.first?.fraction == 1)
        #expect(axis?.second?.fraction == 0.5)
        #expect(axis?.second?.remainderFraction == 0.5)
    }

    /// The shared extent is the **larger** of the two, never an average, a sum, or the first side's.
    @Test("the shared extent is the longer file's own, from either side")
    func sharedIsTheMaximum() {
        #expect(
            PairedWaveformAxis(first: stream(rate: 48_000, seconds: 2), second: stream(rate: 48_000, seconds: 7))?
                .sharedSeconds == 7
        )
        #expect(
            PairedWaveformAxis(first: stream(rate: 48_000, seconds: 7), second: stream(rate: 48_000, seconds: 2))?
                .sharedSeconds == 7
        )
    }

    // MARK: - Time, not frames

    /// **The comparison is temporal.** Two files of the same duration at different rates hold different
    /// frame counts — 132 300 against 144 000 — and comparing frames would report a difference in time
    /// where there is none.
    @Test("the same duration at two different sample rates is the same length on the axis")
    func differentRatesSameDuration() {
        let first = stream(rate: 44_100, frames: 132_300) // 3.0 s
        let second = stream(rate: 48_000, frames: 144_000) // 3.0 s
        #expect(first.frameCount != second.frameCount, "the fixture no longer discriminates")

        let axis = PairedWaveformAxis(first: first, second: second)
        #expect(axis?.sharedSeconds == 3)
        #expect(axis?.first?.fraction == 1)
        #expect(axis?.second?.fraction == 1)
    }

    /// And the converse: **more frames is not more time.** The 44.1 kHz file holds more frames and lasts
    /// less, and the axis says so.
    @Test("more frames at a lower rate is still less time")
    func moreFramesLessTime() {
        let first = stream(rate: 44_100, frames: 88_200) // 2.0 s, 88 200 frames
        let second = stream(rate: 192_000, frames: 768_000) // 4.0 s, 768 000 frames
        #expect(first.frameCount < second.frameCount)

        let axis = PairedWaveformAxis(first: first, second: second)
        #expect(axis?.sharedSeconds == 4)
        #expect(axis?.first?.fraction == 0.5)
        #expect(axis?.second?.fraction == 1)
    }

    /// A ratio that is not a round fraction, so the arithmetic is exercised rather than the fixtures.
    @Test("a non-trivial ratio between two rates and two lengths")
    func aNonTrivialRatio() {
        let first = stream(rate: 44_100, frames: 110_250) // 2.5 s
        let second = stream(rate: 48_000, frames: 192_000) // 4.0 s
        guard let axis = PairedWaveformAxis(first: first, second: second) else {
            Issue.record("no axis for two real streams"); return
        }
        #expect(axis.sharedSeconds == 4)
        #expect(abs((axis.first?.fraction ?? 0) - 0.625) < 1e-12)
        #expect(axis.second?.fraction == 1)
    }

    // MARK: - Bounds the type must hold

    @Test("no fraction ever exceeds one, and the longer side is exactly one")
    func fractionsAreBounded() {
        for (a, b) in [(1.0, 9.0), (9.0, 1.0), (3.0, 3.0), (0.25, 60.0)] {
            guard let axis = PairedWaveformAxis(
                first: stream(rate: 48_000, seconds: a), second: stream(rate: 48_000, seconds: b)
            ) else {
                Issue.record("no axis for \(a) s against \(b) s"); return
            }
            let first = axis.first?.fraction ?? .nan
            let second = axis.second?.fraction ?? .nan
            #expect(first > 0 && first <= 1, "first fraction \(first) for \(a) s against \(b) s")
            #expect(second > 0 && second <= 1, "second fraction \(second) for \(a) s against \(b) s")
            #expect(max(first, second) == 1, "neither side reached the whole axis")
            #expect(first.isFinite && second.isFinite)
        }
    }

    /// A stream is a real answer for a file that opened and holds no audio. It occupies none of the
    /// axis — which is different from having no lane at all.
    @Test("a file with no audio occupies none of the axis, and still has a lane")
    func aFileWithNoAudio() {
        let axis = PairedWaveformAxis(
            first: stream(rate: 44_100, frames: 0), second: stream(rate: 44_100, seconds: 4)
        )
        #expect(axis?.sharedSeconds == 4)
        #expect(axis?.first?.seconds == 0)
        #expect(axis?.first?.fraction == 0)
        #expect(axis?.first?.remainderFraction == 1)
    }

    /// *No extent was measured* is not *this file lasts no time*, and the type keeps them apart.
    @Test("a read that reported no stream gets no lane, never a lane of zero")
    func noStreamIsNotZero() {
        let axis = PairedWaveformAxis(first: nil, second: stream(rate: 44_100, seconds: 4))
        #expect(axis?.sharedSeconds == 4)
        #expect(axis?.first == nil)
        #expect(axis?.second?.fraction == 1)
    }

    @Test("there is no axis when neither file has any audio to lay out")
    func noAxisAtAll() {
        #expect(PairedWaveformAxis(first: nil, second: nil) == nil)
        #expect(PairedWaveformAxis(
            first: stream(rate: 44_100, frames: 0), second: stream(rate: 48_000, frames: 0)
        ) == nil)
        #expect(PairedWaveformAxis(first: stream(rate: 44_100, frames: 0), second: nil) == nil)
    }

    // MARK: - The existing bucket arithmetic, reused unchanged

    /// **A short file stops where its audio stops.** The lane's own geometry is the one a single file
    /// gets, at the width its duration earns — the last bucket's trailing edge is the lane's width, not
    /// the pair's.
    @Test("each side's buckets are laid out by the existing geometry, inside its own lane")
    func bucketsAreLaidOutInsideTheLane() {
        let axis = PairedWaveformAxis(
            first: stream(rate: 44_100, seconds: 5), second: stream(rate: 44_100, seconds: 10)
        )!
        let laneSize = axis.laneSize(.first, in: total)!
        #expect(laneSize == CGSize(width: 400, height: 100))

        let buckets = envelope(peaks: [0.1, 0.2, 0.3, 0.4]).buckets
        guard let lane = WaveformGeometry(size: laneSize, bucketCount: buckets.count),
              let alone = WaveformGeometry(size: laneSize, bucketCount: buckets.count)
        else {
            Issue.record("no geometry for a lane of \(laneSize)"); return
        }
        // Identical to what one file alone gets at that size: the arithmetic is reused, not replaced.
        for index in buckets.indices {
            #expect(lane.horizontalBand(forBucket: index)?.minX == alone.horizontalBand(forBucket: index)?.minX)
            #expect(lane.horizontalBand(forBucket: index)?.maxX == alone.horizontalBand(forBucket: index)?.maxX)
        }
        // And it ends at the lane's width — half the pair's — rather than filling the axis.
        #expect(lane.horizontalBand(forBucket: buckets.count - 1)?.maxX == 400)
        #expect(lane.horizontalBand(forBucket: 0)?.minX == 0)
    }

    /// **Nothing is drawn in the remainder.** No bucket maps into it, and no bucket is invented to fill
    /// it: the geometry knows exactly the envelope's own count and refuses an index past it.
    @Test("the remainder carries no drawn value at all")
    func theRemainderIsEmpty() {
        let axis = PairedWaveformAxis(
            first: stream(rate: 44_100, seconds: 4), second: stream(rate: 44_100, seconds: 16)
        )!
        let produced = envelope(peaks: [0.5, 0.5, 0.5])
        let laneSize = axis.laneSize(.first, in: total)!
        #expect(laneSize.width == 200) // a quarter of 800

        let lane = WaveformGeometry(size: laneSize, bucketCount: produced.buckets.count)!
        #expect(lane.bucketCount == produced.buckets.count)
        // Every band is inside the lane, and nothing exists past it.
        for index in produced.buckets.indices {
            #expect((lane.horizontalBand(forBucket: index)?.maxX ?? .infinity) <= laneSize.width)
        }
        #expect(lane.horizontalBand(forBucket: produced.buckets.count) == nil)
        #expect(lane.horizontalBand(forBucket: -1) == nil)
        // The remainder is three quarters of the axis, and it is stated rather than filled.
        #expect(axis.first?.remainderFraction == 0.75)
    }

    /// A file with no audio beside one that has some earns a lane of zero width, which no geometry can
    /// be built for — so nothing is drawn, rather than something being stretched into place.
    @Test("a zero-width lane yields no geometry at all")
    func aZeroWidthLaneDrawsNothing() {
        let axis = PairedWaveformAxis(
            first: stream(rate: 44_100, frames: 0), second: stream(rate: 44_100, seconds: 4)
        )!
        let laneSize = axis.laneSize(.first, in: total)!
        #expect(laneSize.width == 0)
        #expect(WaveformGeometry(size: laneSize, bucketCount: 3) == nil)
    }

    // MARK: - The data is untouched

    /// **The same envelope, in two different pairings.** Laying a file out beside a longer one changes
    /// no bucket, adds none, and removes none — the axis never sees an envelope at all.
    @Test("an envelope is identical whatever it is paired with")
    func theEnvelopeIsUnchanged() {
        let produced = envelope(peaks: [0.1, 0.9, 0.4])
        let before = produced.buckets

        _ = PairedWaveformAxis(
            first: stream(rate: 44_100, seconds: 3), second: stream(rate: 44_100, seconds: 3)
        )
        _ = PairedWaveformAxis(
            first: stream(rate: 44_100, seconds: 3), second: stream(rate: 44_100, seconds: 300)
        )

        #expect(produced.buckets == before)
        #expect(produced.buckets.count == 3, "a bucket was added or removed")
        #expect(!produced.buckets.contains(WaveformBucket.silent), "a silent bucket was introduced")
        #expect(produced.buckets.map(\.maximum) == [0.1, 0.9, 0.4])
        #expect(produced.buckets.map(\.minimum) == [-0.1, -0.9, -0.4])
    }

    /// **Amplitude is not part of the comparison.** The same amplitude lands at the same height in both
    /// lanes, whatever their widths, because the scale is a property of the drawing and not of a file.
    @Test("both lanes are driven by the same amplitude range, and the same height")
    func amplitudeIsSharedAndFixed() {
        let axis = PairedWaveformAxis(
            first: stream(rate: 44_100, seconds: 2), second: stream(rate: 44_100, seconds: 8)
        )!
        #expect(axis.amplitudeRange(for: .first) == axis.amplitudeRange(for: .second))
        #expect(axis.amplitudeRange(for: .first) == WaveformGeometry.drawnRange)
        #expect(axis.amplitudeRange(for: .first) == -1 ... 1)

        // The two lanes differ in width and not in height, so a level reads the same in both.
        let firstLane = WaveformGeometry(size: axis.laneSize(.first, in: total)!, bucketCount: 4)!
        let secondLane = WaveformGeometry(size: axis.laneSize(.second, in: total)!, bucketCount: 4)!
        #expect(firstLane.size.width != secondLane.size.width)
        for amplitude: Float in [-1, -0.5, 0, 0.25, 0.75, 1] {
            #expect(firstLane.y(forAmplitude: amplitude) == secondLane.y(forAmplitude: amplitude))
        }
        #expect(firstLane.centreY == secondLane.centreY)
    }

    /// The two sides stay distinguishable: a pair is not a merge, and neither side's numbers become the
    /// other's.
    @Test("the two sides remain separately readable")
    func theTwoSidesStayApart() {
        let axis = PairedWaveformAxis(
            first: stream(rate: 44_100, seconds: 2), second: stream(rate: 48_000, seconds: 8)
        )!
        #expect(axis.first != axis.second)
        #expect(axis.first?.seconds == 2)
        #expect(axis.second?.seconds == 8)
        #expect(axis.lane(.first) == axis.first)
        #expect(axis.lane(.second) == axis.second)
    }
}
