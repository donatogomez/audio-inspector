import CoreGraphics
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// Group 5's subject: **two spectral grids on one time axis and one frequency axis, as arithmetic.**
//
// Nothing here renders. What is asserted is the shared extents, each side's share of them, that the
// share is handed to the *existing* band arithmetic rather than replacing it, that the range a file
// cannot represent is not the range where it measured silence, and that laying two grids out together
// changes neither grid.

@Suite("Feature — two spectrograms on one time and one frequency axis")
struct PairedSpectrogramAxesTests {

    // MARK: - Fixtures

    private func stream(rate: Double, seconds: Double) -> PCMStreamDescription {
        PCMStreamDescription(sampleRate: rate, channelCount: 2, frameCount: Int(rate * seconds))!
    }

    private func model(rate: Double, columns: Int = 2, bands: Int = 4) -> Spectrogram {
        Spectrogram(
            values: Array(repeating: Float(-30), count: columns * bands),
            columnCount: columns,
            bandCount: bands,
            sampleRate: rate,
            frameCount: 4_096,
            channelCount: 2
        )!
    }

    private let total = CGSize(width: 800, height: 400)

    // MARK: - 5.1 — time is group 4's, and cannot disagree with it

    /// The same two streams give the same time fractions to both kinds of drawing, because the
    /// spectrogram does not compute them: it composes the value that does.
    @Test("a waveform lane and a spectrogram lane agree about how long a file is")
    func timeAgreesWithGroupFour() {
        for (a, b) in [(3.0, 3.0), (5.0, 10.0), (10.0, 5.0), (2.5, 4.0)] {
            let first = stream(rate: 44_100, seconds: a)
            let second = stream(rate: 48_000, seconds: b)
            guard let waveform = PairedWaveformAxis(first: first, second: second),
                  let spectrogram = PairedSpectrogramAxes(first: first, second: second)
            else {
                Issue.record("no axes for \(a) s against \(b) s"); return
            }
            #expect(spectrogram.sharedSeconds == waveform.sharedSeconds)
            #expect(spectrogram.first?.timeFraction == waveform.first?.fraction)
            #expect(spectrogram.second?.timeFraction == waveform.second?.fraction)
            #expect(spectrogram.first?.seconds == waveform.first?.seconds)
        }
    }

    @Test("there are no axes where there is no time axis")
    func noTimeAxisMeansNoAxes() {
        #expect(PairedSpectrogramAxes(first: nil, second: nil) == nil)
        #expect(PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 0), second: stream(rate: 96_000, seconds: 0)
        ) == nil)
    }

    // MARK: - 5.2 — the shared frequency extent

    @Test("two files at the same rate each reach the whole frequency axis")
    func sameRate() {
        let axes = PairedSpectrogramAxes(
            first: stream(rate: 48_000, seconds: 3), second: stream(rate: 48_000, seconds: 3)
        )
        #expect(axes?.sharedNyquist == 24_000)
        #expect(axes?.first?.frequencyFraction == 1)
        #expect(axes?.second?.frequencyFraction == 1)
        #expect(axes?.first?.outOfRangeFraction == 0)
        #expect(axes?.second?.outOfRangeFraction == 0)
    }

    /// 44.1 kHz beside 96 kHz: the shared axis reaches 48 kHz, and the lower file stops at 22.05 kHz —
    /// **shorter on the axis, not rescaled to match**.
    @Test("a 44.1 kHz file beside a 96 kHz one reaches 22050 of 48000")
    func firstHasTheLowerNyquist() {
        let axes = PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 3), second: stream(rate: 96_000, seconds: 3)
        )
        #expect(axes?.sharedNyquist == 48_000)
        #expect(axes?.first?.nyquist == 22_050)
        #expect(axes?.first?.frequencyFraction == 22_050.0 / 48_000.0)
        #expect(axes?.second?.frequencyFraction == 1)
        #expect(axes?.first?.outOfRangeFraction == 1 - 22_050.0 / 48_000.0)
    }

    /// The same pair the other way round: the rule is not order-dependent.
    @Test("a 96 kHz file beside a 44.1 kHz one gives the mirror answer")
    func secondHasTheLowerNyquist() {
        let axes = PairedSpectrogramAxes(
            first: stream(rate: 96_000, seconds: 3), second: stream(rate: 44_100, seconds: 3)
        )
        #expect(axes?.sharedNyquist == 48_000)
        #expect(axes?.first?.frequencyFraction == 1)
        #expect(axes?.second?.nyquist == 22_050)
        #expect(axes?.second?.frequencyFraction == 22_050.0 / 48_000.0)
    }

    @Test("96 kHz beside 192 kHz is half the axis, in either order")
    func ninetySixAgainstOneNinetyTwo() {
        let high = PairedSpectrogramAxes(
            first: stream(rate: 96_000, seconds: 1), second: stream(rate: 192_000, seconds: 1)
        )
        #expect(high?.sharedNyquist == 96_000)
        #expect(high?.first?.frequencyFraction == 0.5)
        #expect(high?.second?.frequencyFraction == 1)

        let reversed = PairedSpectrogramAxes(
            first: stream(rate: 192_000, seconds: 1), second: stream(rate: 96_000, seconds: 1)
        )
        #expect(reversed?.first?.frequencyFraction == 1)
        #expect(reversed?.second?.frequencyFraction == 0.5)
    }

    @Test("no frequency fraction exceeds one, and the higher-rate side is exactly one")
    func frequencyFractionsAreBounded() {
        for (a, b) in [(44_100.0, 96_000.0), (96_000.0, 44_100.0), (48_000.0, 48_000.0), (8_000.0, 192_000.0)] {
            guard let axes = PairedSpectrogramAxes(
                first: stream(rate: a, seconds: 1), second: stream(rate: b, seconds: 1)
            ) else {
                Issue.record("no axes for \(a) Hz against \(b) Hz"); return
            }
            let first = axes.first?.frequencyFraction ?? .nan
            let second = axes.second?.frequencyFraction ?? .nan
            #expect(first > 0 && first <= 1, "first fraction \(first) for \(a) against \(b)")
            #expect(second > 0 && second <= 1, "second fraction \(second) for \(a) against \(b)")
            #expect(max(first, second) == 1, "neither side reached the whole frequency axis")
            #expect(axes.sharedNyquist == max(a, b) / 2)
        }
    }

    // MARK: - 5.3 — above a file's Nyquist there is no cell, and the axis is the shared one

    @Test("the grid occupies only its own share, from 0 Hz up, and nothing is drawn above it")
    func theGridStopsAtItsOwnNyquist() {
        let axes = PairedSpectrogramAxes(
            first: stream(rate: 48_000, seconds: 4), second: stream(rate: 96_000, seconds: 4)
        )!
        // 24 000 of 48 000: half the height, sitting at the bottom.
        let occupied = axes.occupiedRect(.first, in: total)!
        #expect(occupied == CGRect(x: 0, y: 200, width: 800, height: 200))

        let outOfRange = axes.outOfRangeRect(.first, in: total)!
        #expect(outOfRange == CGRect(x: 0, y: 0, width: 800, height: 200))
        #expect(!occupied.intersects(outOfRange), "the two regions overlap")

        // The existing band arithmetic, handed the occupied rect, lands entirely inside it.
        let grid = model(rate: 48_000, columns: 3, bands: 5)
        let geometry = SpectrogramGeometry(size: occupied.size, model: grid)!
        for band in 0 ..< grid.bandCount {
            guard let vertical = geometry.verticalBand(forBand: band) else {
                Issue.record("no vertical band for \(band)"); return
            }
            #expect(vertical.minY >= 0 && vertical.maxY <= occupied.height)
        }
        // And nothing exists past the model's own bands.
        #expect(geometry.verticalBand(forBand: grid.bandCount) == nil)
        #expect(geometry.verticalBand(forBand: -1) == nil)
    }

    /// The axis is labelled to the **shared** Nyquist. Cropping to the lower one would hide the higher
    /// file's upper range, which is the thing a collector is looking for.
    @Test("the frequency axis is labelled to the shared Nyquist, not the lower one")
    func theAxisIsLabelledToTheSharedNyquist() {
        let axes = PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 3), second: stream(rate: 96_000, seconds: 3)
        )!
        let marks = SpectrogramAxes.frequencyMarks(nyquist: axes.sharedNyquist)
        #expect(marks.last == 48_000, "the axis stopped at \(String(describing: marks.last))")
        #expect(marks.last != axes.first?.nyquist, "the axis was cropped to the lower Nyquist")
        #expect(marks.first == 0)
    }

    // MARK: - 5.4 — the range that is not the floor

    /// **The two absences must not look the same.** The treatment above a file's Nyquist is achromatic,
    /// and no colour the ramp produces ever is — so it cannot be mistaken for any level, least of all
    /// the near-black drawn at the floor.
    @Test("the out-of-range treatment is not the colour the ramp draws at the floor")
    func outOfRangeIsNotTheFloor() {
        let floor = SpectrogramColourRamp.components(for: Spectrogram.floorDecibels)
        let outOfRange = PairedSpectrogramAxes.outOfRangeTreatment

        #expect(outOfRange != floor)
        // Not merely different: separable. The floor is near-black, and this is mid-grey.
        let floorLuminance = 0.2126 * floor.red + 0.7152 * floor.green + 0.0722 * floor.blue
        let outLuminance = 0.2126 * outOfRange.red + 0.7152 * outOfRange.green + 0.0722 * outOfRange.blue
        #expect(outLuminance - floorLuminance > 0.2, "\(outLuminance) against \(floorLuminance)")
    }

    /// The structural half of the same claim: it is not any level the ramp can produce, because the ramp
    /// never produces an equal-component colour and this treatment is one.
    @Test("no level on the ramp is achromatic, and the out-of-range treatment is")
    func theRampIsNeverAchromatic() {
        let treatment = PairedSpectrogramAxes.outOfRangeTreatment
        #expect(treatment.red == treatment.green && treatment.green == treatment.blue)

        for step in 0 ... 240 {
            let decibels = Float(-120 + step * 1) // −120 … +120 dBFS, past both ends of the ramp
            let components = SpectrogramColourRamp.components(for: decibels)
            #expect(
                components.red != components.blue,
                "the ramp produced an achromatic colour at \(decibels) dBFS: \(components)"
            )
            #expect(
                (components.red, components.green, components.blue) != treatment,
                "the ramp reproduced the out-of-range treatment at \(decibels) dBFS"
            )
        }
    }

    // MARK: - 5.5 — one ramp, one floor, one legend

    @Test("both lanes are driven by the same energy range, the same floor and one legend")
    func oneRampForBoth() {
        let axes = PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 2), second: stream(rate: 96_000, seconds: 8)
        )!
        #expect(axes.energyRange(for: .first) == axes.energyRange(for: .second))
        #expect(axes.energyRange(for: .first) == SpectrogramColourRamp.range)
        #expect(axes.floorDecibels(for: .first) == axes.floorDecibels(for: .second))
        #expect(axes.floorDecibels(for: .first) == Spectrogram.floorDecibels)
        #expect(axes.floorDecibels(for: .first) == -120)

        // One legend, describing both: the swatches and the ticks are the ramp's own, not a lane's.
        #expect(!SpectrogramColourRamp.legendStops().isEmpty)
        #expect(!SpectrogramColourRamp.legendTicks.isEmpty)
        // The same level is the same colour whichever lane asks.
        for decibels: Float in [-120, -90, -60, -30, 0] {
            let asFirst = SpectrogramColourRamp.components(for: decibels)
            let asSecond = SpectrogramColourRamp.components(for: decibels)
            #expect(asFirst == asSecond)
        }
    }

    // MARK: - Time and frequency are independent

    /// A file can take the whole width and half the height, or half the width and the whole height, and
    /// the two rules never consult one another.
    @Test("the time axis and the frequency axis are computed independently")
    func timeAndFrequencyAreIndependent() {
        // Same duration, different rates: full width, unequal heights.
        let sameLength = PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 4), second: stream(rate: 96_000, seconds: 4)
        )!
        #expect(sameLength.first?.timeFraction == 1)
        #expect(sameLength.second?.timeFraction == 1)
        #expect(sameLength.first?.frequencyFraction != 1)
        #expect(sameLength.second?.frequencyFraction == 1)

        // Same rate, different durations: unequal widths, full heights.
        let sameRate = PairedSpectrogramAxes(
            first: stream(rate: 48_000, seconds: 2), second: stream(rate: 48_000, seconds: 8)
        )!
        #expect(sameRate.first?.timeFraction == 0.25)
        #expect(sameRate.first?.frequencyFraction == 1)
        #expect(sameRate.second?.frequencyFraction == 1)

        // Both different: less than all of each.
        let both = PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 2), second: stream(rate: 96_000, seconds: 8)
        )!
        #expect(both.first?.timeFraction == 0.25)
        #expect(both.first?.frequencyFraction == 22_050.0 / 48_000.0)
        #expect(both.second?.timeFraction == 1)
        #expect(both.second?.frequencyFraction == 1)

        // And the rects say the same thing: a quarter of the width, under half the height.
        let occupied = both.occupiedRect(.first, in: total)!
        #expect(occupied.width == 200)
        #expect(occupied.height < total.height / 2)
    }

    // MARK: - The grid's own numbers decide nothing about the axes

    /// `bandCount` is the grid's resolution and says nothing about frequency; `columnCount` is its time
    /// resolution and says nothing about duration. Two models with identical counts can describe
    /// entirely different extents.
    @Test("band and column counts do not determine the extents")
    func theGridsCountsAreNotTheExtents() {
        let low = model(rate: 44_100, columns: 8, bands: 16)
        let high = model(rate: 192_000, columns: 8, bands: 16)
        #expect(low.bandCount == high.bandCount)
        #expect(low.columnCount == high.columnCount)
        #expect(low.nyquist != high.nyquist)

        let axes = PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 1), second: stream(rate: 192_000, seconds: 4)
        )!
        #expect(axes.sharedNyquist == 96_000)
        #expect(axes.first?.frequencyFraction == 22_050.0 / 96_000.0)
        #expect(axes.first?.timeFraction == 0.25)
    }

    /// The description is the single source, and the model built from it agrees — verified rather than
    /// assumed, so choosing one source is a decision and not a guess.
    @Test("the stream description and a model built from it report the same Nyquist")
    func theTwoSourcesAgree() {
        let description = stream(rate: 96_000, seconds: 1)
        let built = model(rate: description.sampleRate)
        #expect(built.nyquist == description.sampleRate / 2)
        let axes = PairedSpectrogramAxes(first: description, second: stream(rate: 96_000, seconds: 1))!
        #expect(axes.sharedNyquist == built.nyquist)
    }

    // MARK: - 5.8 — the raster is still the model's own size, and still uninterpolated

    @Test("each lane's raster is exactly its model's cells, whatever the lane's size")
    func rastersAreModelSized() {
        let axes = PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 2), second: stream(rate: 96_000, seconds: 8)
        )!
        let lowRate = model(rate: 44_100, columns: 7, bands: 11)
        let highRate = model(rate: 96_000, columns: 13, bands: 17)

        for (side, grid) in [(PairedSpectrogramAxes.Side.first, lowRate), (.second, highRate)] {
            guard let buffer = SpectrogramRaster.buffer(for: grid) else {
                Issue.record("no raster for \(grid.columnCount)×\(grid.bandCount)"); return
            }
            #expect(buffer.width == grid.columnCount)
            #expect(buffer.height == grid.bandCount)
            #expect(buffer.pixels.count == grid.columnCount * grid.bandCount * SpectrogramRaster.bytesPerPixel)
            // The lane's own area is a drawing size, never a raster size: no resampling happens here.
            let occupied = axes.occupiedRect(side, in: total)!
            #expect(occupied.width != CGFloat(buffer.width) || occupied.height != CGFloat(buffer.height))
        }
    }

    // MARK: - The models are untouched

    @Test("a model is identical whatever it is paired with")
    func theModelIsUnchanged() {
        let grid = model(rate: 44_100, columns: 3, bands: 4)
        let before = grid.values

        _ = PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 3), second: stream(rate: 44_100, seconds: 3)
        )
        _ = PairedSpectrogramAxes(
            first: stream(rate: 44_100, seconds: 3), second: stream(rate: 192_000, seconds: 300)
        )

        #expect(grid.values == before)
        #expect(grid.columnCount == 3)
        #expect(grid.bandCount == 4)
        #expect(grid.sampleRate == 44_100)
        #expect(grid.values.allSatisfy { $0 == -30 }, "a value was re-ranged or normalised")
        #expect(grid.values.allSatisfy { $0 >= Spectrogram.floorDecibels })
    }
}
