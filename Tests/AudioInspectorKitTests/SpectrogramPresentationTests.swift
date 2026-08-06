import AudioInspectorDomain
import CoreGraphics
@testable import FeatureAnalysis
import Foundation
import Testing

// The spectrogram's presentation, asserted over its arithmetic and its words rather than over pixels.
// Nothing here renders: a Canvas cannot be inspected, and everything worth guaranteeing — orientation,
// tiling, the ramp's ordering, the axis's reach, the copy — is decidable without one.

private func model(
    columns: Int, bands: Int, sampleRate: Double = 44_100,
    frameCount: Int = 44_100, channels: Int = 1, value: Float = -60
) throws -> Spectrogram {
    try #require(Spectrogram(
        values: [Float](repeating: value, count: columns * bands),
        columnCount: columns, bandCount: bands,
        sampleRate: sampleRate, frameCount: frameCount, channelCount: channels
    ))
}

@Suite("Presentation — spectrogram geometry")
struct SpectrogramGeometryTests {
    private let area = CGSize(width: 800, height: 400)

    /// The orientation a reader expects, and the one the axis labels promise: the lowest frequency at
    /// the foot of the drawing.
    @Test("band 0 is at the bottom and the highest band at the top")
    func lowFrequenciesSitAtTheBottom() throws {
        let geometry = try #require(SpectrogramGeometry(size: area, columnCount: 4, bandCount: 8))
        let lowest = try #require(geometry.verticalBand(forBand: 0))
        let highest = try #require(geometry.verticalBand(forBand: 7))

        #expect(lowest.minY > highest.minY, "the lowest band was drawn above the highest")
        #expect(abs(lowest.maxY - area.height) < 1e-9, "band 0 does not reach the bottom edge")
        #expect(abs(highest.minY - 0) < 1e-9, "the top band does not reach the top edge")
    }

    @Test("the first column is leftmost and the last reaches the right edge")
    func timeRunsLeftToRight() throws {
        let geometry = try #require(SpectrogramGeometry(size: area, columnCount: 10, bandCount: 4))
        let first = try #require(geometry.horizontalBand(forColumn: 0))
        let last = try #require(geometry.horizontalBand(forColumn: 9))

        #expect(abs(first.minX - 0) < 1e-9)
        #expect(abs(last.maxX - area.width) < 1e-9)
        #expect(first.maxX < last.minX)
    }

    /// Edges computed from indices rather than accumulated from a step: one cell's trailing edge is
    /// exactly the next one's leading edge, at any size and any count.
    @Test("cells tile the area with no gap and no overlap", arguments: [1, 2, 7, 1_024])
    func cellsTileWithoutGaps(columnCount: Int) throws {
        let geometry = try #require(SpectrogramGeometry(size: area, columnCount: columnCount, bandCount: 512))
        for column in 0 ..< (columnCount - 1) {
            let this = try #require(geometry.horizontalBand(forColumn: column))
            let next = try #require(geometry.horizontalBand(forColumn: column + 1))
            #expect(this.maxX == next.minX, "a gap or overlap at column \(column)")
        }
        for band in 0 ..< 511 {
            let this = try #require(geometry.verticalBand(forBand: band))
            let next = try #require(geometry.verticalBand(forBand: band + 1))
            #expect(this.minY == next.maxY, "a gap or overlap at band \(band)")
        }
    }

    /// Non-square dimensions on purpose: a transposed mapping would pass a square test and fail here.
    @Test("columns map to width and bands to height, never the other way round")
    func axesAreNotTransposed() throws {
        let geometry = try #require(
            SpectrogramGeometry(size: CGSize(width: 1_000, height: 100), columnCount: 10, bandCount: 5)
        )
        let cell = try #require(geometry.cell(column: 0, band: 0))
        #expect(abs(cell.width - 100) < 1e-9, "a column did not take one tenth of the width")
        #expect(abs(cell.height - 20) < 1e-9, "a band did not take one fifth of the height")
    }

    @Test("a degenerate area or an empty model yields no geometry", arguments: [
        (CGSize(width: 0, height: 100), 4, 4),
        (CGSize(width: 100, height: 0), 4, 4),
        (CGSize(width: 100, height: 100), 0, 4),
        (CGSize(width: 100, height: 100), 4, 0),
    ])
    func degenerateInputsAreRefused(size: CGSize, columns: Int, bands: Int) {
        #expect(SpectrogramGeometry(size: size, columnCount: columns, bandCount: bands) == nil)
    }

    @Test("a single cell fills the whole area")
    func oneCellFillsEverything() throws {
        let geometry = try #require(SpectrogramGeometry(size: area, columnCount: 1, bandCount: 1))
        let cell = try #require(geometry.cell(column: 0, band: 0))
        #expect(cell == CGRect(origin: .zero, size: area))
    }

    /// More cells than points. Every cell must still be drawn at a visible size rather than rounding
    /// away to nothing and leaving gaps that read as silence.
    @Test("cells stay visible when the model is larger than the area")
    func moreCellsThanPoints() throws {
        let geometry = try #require(
            SpectrogramGeometry(size: CGSize(width: 200, height: 100), columnCount: 1_024, bandCount: 512)
        )
        for column in [0, 500, 1_023] {
            for band in [0, 255, 511] {
                let cell = try #require(geometry.cell(column: column, band: band))
                #expect(cell.width >= SpectrogramGeometry.minimumCellSize)
                #expect(cell.height >= SpectrogramGeometry.minimumCellSize)
            }
        }
    }

    @Test("the full production grid maps without a gap")
    func productionGridMaps() throws {
        let geometry = try #require(SpectrogramGeometry(size: area, columnCount: 1_024, bandCount: 512))
        #expect(geometry.cell(column: 1_023, band: 511) != nil)
        #expect(geometry.cell(column: 1_024, band: 0) == nil)
        #expect(geometry.cell(column: 0, band: 512) == nil)
    }

    @Test("0 Hz sits at the bottom and Nyquist at the top of the frequency axis")
    func frequencyAxisOrientation() throws {
        let geometry = try #require(SpectrogramGeometry(size: area, columnCount: 4, bandCount: 4))
        #expect(try #require(geometry.y(forFrequency: 0, nyquist: 22_050)) == area.height)
        #expect(try #require(geometry.y(forFrequency: 22_050, nyquist: 22_050)) == 0)
        #expect(try #require(geometry.y(forFrequency: 11_025, nyquist: 22_050)) == area.height / 2)
        #expect(geometry.y(forFrequency: 30_000, nyquist: 22_050) == nil)
    }
}

@Suite("Presentation — spectrogram colour ramp")
struct SpectrogramColourRampTests {
    /// The floor is the darkest thing the ramp can draw and full scale the lightest.
    @Test("the floor maps to the bottom of the ramp and full scale to the top")
    func endsOfTheRamp() {
        #expect(SpectrogramColourRamp.position(for: -120) == 0)
        #expect(SpectrogramColourRamp.position(for: 0) == 1)
    }

    /// **A value above 0 dBFS is real and maps to the top**, rather than being discarded — and the model
    /// it came from is not touched, because this type has no way to touch it.
    @Test("values above full scale map to the top of the ramp", arguments: [Float(0.1), 3.52, 12])
    func aboveFullScaleMapsToTheTop(value: Float) {
        #expect(SpectrogramColourRamp.position(for: value) == 1)
    }

    @Test("values below the floor map to the bottom", arguments: [Float(-121), -200])
    func belowTheFloorMapsToTheBottom(value: Float) {
        #expect(SpectrogramColourRamp.position(for: value) == 0)
    }

    @Test("the position rises monotonically with level")
    func positionIsMonotonic() {
        var previous = -1.0
        for level in stride(from: Float(-120), through: 0, by: 2) {
            let position = SpectrogramColourRamp.position(for: level)
            #expect(position >= previous, "the ramp went backwards at \(level) dBFS")
            previous = position
        }
    }

    /// **Strictly increasing luminance** is what keeps the drawing readable in greyscale and under
    /// colour vision deficiency: the ordering survives when hue does not.
    @Test("luminance rises strictly from the floor to full scale")
    func luminanceIsStrictlyIncreasing() {
        var previous = -1.0
        for level in stride(from: Float(-120), through: 0, by: 5) {
            let luminance = SpectrogramColourRamp.luminance(for: level)
            #expect(luminance > previous, "luminance did not rise at \(level) dBFS")
            previous = luminance
        }
        #expect(SpectrogramColourRamp.luminance(for: -120) < 0.1, "the floor is not dark")
        #expect(SpectrogramColourRamp.luminance(for: 0) > 0.85, "full scale is not light")
    }

    @Test("the ramp is deterministic")
    func rampIsDeterministic() {
        for level in stride(from: Float(-120), through: 0, by: 7) {
            let first = SpectrogramColourRamp.components(for: level)
            let second = SpectrogramColourRamp.components(for: level)
            #expect(first == second)
        }
    }

    /// No green-good, no red-bad. Asserted structurally: at no point is the ramp dominantly red or
    /// dominantly green in the way a success/failure palette would be.
    @Test("the ramp carries no success or failure semantics")
    func noQualitySemantics() {
        for level in stride(from: Float(-120), through: 0, by: 2) {
            let c = SpectrogramColourRamp.components(for: level)
            let redDominant = c.red > c.green + 0.25 && c.red > c.blue + 0.25
            let greenDominant = c.green > c.red + 0.25 && c.green > c.blue + 0.25
            #expect(!redDominant, "the ramp is red at \(level) dBFS")
            #expect(!greenDominant, "the ramp is green at \(level) dBFS")
        }
    }

    /// A non-finite value cannot come from the domain, but is answered for rather than left to produce
    /// a silent `NaN` coordinate.
    @Test("a non-finite level is treated as the floor", arguments: [Float.nan, .infinity, -.infinity])
    func nonFiniteIsTheFloor(value: Float) {
        #expect(SpectrogramColourRamp.position(for: value) == 0)
    }

    /// The ramp reads the model and never writes to it.
    @Test("colouring a model leaves it structurally intact")
    func theModelIsNeverModified() throws {
        let original = try model(columns: 8, bands: 8, value: 12)
        for column in 0 ..< original.columnCount {
            for band in 0 ..< original.bandCount {
                _ = SpectrogramColourRamp.colour(for: try #require(original.value(column: column, band: band)))
            }
        }
        let again = try model(columns: 8, bands: 8, value: 12)
        #expect(original == again)
        #expect(original.values.allSatisfy { $0 == 12 }, "a value above full scale was written back")
    }

    @Test("the legend states the range in numbers")
    func legendIsNumeric() {
        #expect(SpectrogramColourRamp.legendTicks.first == -120)
        #expect(SpectrogramColourRamp.legendTicks.last == 0)
        #expect(SpectrogramColourRamp.legendTicks.count >= 3, "two numbers alone do not explain a ramp")
        #expect(SpectrogramColourRamp.legendStops().count > 8)
    }
}

@Suite("Presentation — spectrogram axes")
struct SpectrogramAxesTests {
    /// **The axis is never cropped.** At 96 and 192 kHz the empty upper range is the evidence, so it
    /// stays — a top mark at 24 kHz would hide exactly what a collector is looking for.
    @Test(
        "the frequency axis always reaches the file's own Nyquist",
        arguments: [22_050.0, 24_000, 48_000, 96_000]
    )
    func theAxisReachesNyquist(nyquist: Double) {
        let marks = SpectrogramAxes.frequencyMarks(nyquist: nyquist)
        #expect(marks.first == 0, "the axis does not start at 0 Hz")
        #expect(marks.last == nyquist, "the axis stops at \(marks.last ?? -1) instead of \(nyquist)")
        #expect(!marks.contains { $0 > nyquist }, "a mark lies beyond Nyquist")
    }

    @Test("the marks stay countable at every sample rate", arguments: [22_050.0, 24_000, 48_000, 96_000])
    func marksStayLegible(nyquist: Double) {
        let marks = SpectrogramAxes.frequencyMarks(nyquist: nyquist)
        #expect(marks.count >= 4, "too few marks to read the axis at \(nyquist)")
        #expect(marks.count <= 14, "\(marks.count) marks would crowd the axis at \(nyquist)")
    }

    /// Linear, not logarithmic: the gap between consecutive marks is constant apart from the last,
    /// which lands on Nyquist exactly.
    @Test("the frequency marks are evenly spaced")
    func marksAreLinear() {
        let marks = SpectrogramAxes.frequencyMarks(nyquist: 24_000)
        let steps = zip(marks.dropLast().dropLast(), marks.dropFirst()).map { $1 - $0 }
        #expect(Set(steps).count <= 1, "the spacing varies, so the axis is not linear: \(steps)")
    }

    @Test("frequencies are written the way a person reads them")
    func frequenciesAreHuman() {
        #expect(HumanFormat.frequency(0) == "0 Hz")
        #expect(HumanFormat.frequency(500) == "500 Hz")
        #expect(HumanFormat.frequency(2_000) == "2 kHz")
        #expect(HumanFormat.frequency(22_050) == "22.05 kHz")
    }

    @Test("time marks span the file and stay countable", arguments: [0.5, 12.0, 372.0, 3_600.0])
    func timeMarksSpanTheFile(duration: Double) {
        let marks = SpectrogramAxes.timeMarks(duration: duration)
        #expect(marks.first == 0)
        #expect(marks.last == duration)
        #expect(marks.count <= 12, "\(marks.count) time marks would crowd the axis")
    }

    @Test("a duration comes from the model alone")
    func durationFromTheModel() throws {
        let ten = try model(columns: 4, bands: 4, sampleRate: 44_100, frameCount: 441_000)
        #expect(abs(SpectrogramAxes.duration(of: ten) - 10) < 1e-9)
    }

    @Test("an empty file yields no marks")
    func noMarksForNothing() {
        #expect(SpectrogramAxes.timeMarks(duration: 0).isEmpty)
        #expect(SpectrogramAxes.frequencyMarks(nyquist: 0).isEmpty)
    }
}
