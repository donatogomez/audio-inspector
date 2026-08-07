import AudioInspectorDomain
@testable import FeatureAnalysis
import CoreGraphics
import Foundation
import Testing

// The raster renderer's contract, asserted over the buffer rather than over a picture.
//
// No snapshots: a golden image would break on any harmless rendering difference and prove nothing about
// the properties that matter. Every guarantee below — one cell per pixel, band 0 at the bottom, column 0
// at the left, no dependence on the view — is a fact about the bytes, and the bytes are arithmetic.

/// A model whose every cell is distinguishable, so a transposed or flipped layout cannot pass.
private func gradientModel(columns: Int, bands: Int) throws -> Spectrogram {
    var values = [Float](repeating: 0, count: columns * bands)
    for column in 0 ..< columns {
        for band in 0 ..< bands {
            // Distinct per cell, and spread across the whole ramp.
            let t = Float(column * bands + band) / Float(max(1, columns * bands - 1))
            values[column * bands + band] = -120 + t * 120
        }
    }
    return try #require(Spectrogram(
        values: values, columnCount: columns, bandCount: bands,
        sampleRate: 44_100, frameCount: 44_100, channelCount: 2
    ))
}

private func flatModel(columns: Int, bands: Int, level: Float) throws -> Spectrogram {
    try #require(Spectrogram(
        values: [Float](repeating: level, count: columns * bands),
        columnCount: columns, bandCount: bands,
        sampleRate: 44_100, frameCount: 44_100, channelCount: 1
    ))
}

/// The RGBA quadruple at a logical cell, read through the buffer's own row arithmetic.
private func pixel(
    _ buffer: SpectrogramRaster.Buffer, column: Int, row: Int
) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let offset = row * buffer.bytesPerRow + column * SpectrogramRaster.bytesPerPixel
    return (buffer.pixels[offset], buffer.pixels[offset + 1], buffer.pixels[offset + 2], buffer.pixels[offset + 3])
}

/// What the ramp says a level should be drawn as, converted the same way the raster converts it.
private func expectedPixel(for level: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
    let c = SpectrogramColourRamp.components(for: level)
    func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
    return (byte(c.red), byte(c.green), byte(c.blue))
}

@Suite("Presentation — the spectrogram raster")
struct SpectrogramRasterTests {

    // MARK: Shape

    /// One logical pixel per model cell — not per point, not per view pixel.
    @Test("the buffer is exactly the model's own size", arguments: [(4, 4), (1, 1), (1_024, 512), (7, 3)])
    func bufferMatchesTheModel(columns: Int, bands: Int) throws {
        let model = try gradientModel(columns: columns, bands: bands)
        let buffer = try #require(SpectrogramRaster.buffer(for: model))

        #expect(buffer.width == columns)
        #expect(buffer.height == bands)
        #expect(buffer.bytesPerRow == columns * 4)
        #expect(buffer.pixels.count == columns * bands * 4)
    }

    @Test("the image is the model's own size too")
    func imageMatchesTheModel() throws {
        let model = try gradientModel(columns: 1_024, bands: 512)
        let image = try #require(SpectrogramRaster.image(for: model))
        #expect(image.width == 1_024)
        #expect(image.height == 512)
    }

    // MARK: Orientation — the four assertions a flip or a transpose would break

    /// **Band 0 is the lowest frequency and belongs at the bottom.** The buffer's last row is band 0.
    @Test("band 0 lands on the bottom row")
    func bandZeroIsAtTheBottom() throws {
        let bands = 8
        let model = try gradientModel(columns: 4, bands: bands)
        let buffer = try #require(SpectrogramRaster.buffer(for: model))

        let level = try #require(model.value(column: 0, band: 0))
        let expected = expectedPixel(for: level)
        let bottom = pixel(buffer, column: 0, row: bands - 1)

        #expect((bottom.r, bottom.g, bottom.b) == expected)
    }

    /// And the highest band is the top row.
    @Test("the highest band lands on the top row")
    func highestBandIsAtTheTop() throws {
        let bands = 8
        let model = try gradientModel(columns: 4, bands: bands)
        let buffer = try #require(SpectrogramRaster.buffer(for: model))

        let level = try #require(model.value(column: 0, band: bands - 1))
        let top = pixel(buffer, column: 0, row: 0)

        #expect((top.r, top.g, top.b) == expectedPixel(for: level))
    }

    /// Column 0 is leftmost, so time runs left to right.
    @Test("column 0 is the leftmost column and the last is the rightmost")
    func timeRunsLeftToRight() throws {
        let columns = 6
        let model = try gradientModel(columns: columns, bands: 4)
        let buffer = try #require(SpectrogramRaster.buffer(for: model))

        let first = try #require(model.value(column: 0, band: 0))
        let last = try #require(model.value(column: columns - 1, band: 0))

        let left = pixel(buffer, column: 0, row: 3)
        let right = pixel(buffer, column: columns - 1, row: 3)

        #expect((left.r, left.g, left.b) == expectedPixel(for: first))
        #expect((right.r, right.g, right.b) == expectedPixel(for: last))
    }

    /// Every cell, exhaustively, for a small model: the mapping is total and nothing is transposed.
    @Test("every cell lands where the model says it should")
    func everyCellIsPlacedCorrectly() throws {
        let columns = 5
        let bands = 7
        let model = try gradientModel(columns: columns, bands: bands)
        let buffer = try #require(SpectrogramRaster.buffer(for: model))

        for column in 0 ..< columns {
            for band in 0 ..< bands {
                let level = try #require(model.value(column: column, band: band))
                let actual = pixel(buffer, column: column, row: bands - 1 - band)
                #expect(
                    (actual.r, actual.g, actual.b) == expectedPixel(for: level),
                    "column \(column), band \(band) was drawn wrong"
                )
            }
        }
    }

    // MARK: Colour

    /// The raster uses **the same ramp function** the legend samples, so the two cannot drift.
    @Test("the floor is drawn as the ramp's darkest colour")
    func theFloorIsTheRampsFloor() throws {
        let model = try flatModel(columns: 3, bands: 3, level: Spectrogram.floorDecibels)
        let buffer = try #require(SpectrogramRaster.buffer(for: model))
        let expected = expectedPixel(for: Spectrogram.floorDecibels)

        for column in 0 ..< 3 {
            for row in 0 ..< 3 {
                let p = pixel(buffer, column: column, row: row)
                #expect((p.r, p.g, p.b) == expected)
            }
        }
    }

    /// **A level above full scale is clamped only where it is drawn.** The model keeps the value it
    /// measured; the ramp saturates. Asserted both ways in the same test so neither half drifts.
    @Test("a level above full scale draws as full scale without changing the model", arguments: [Float(0.1), 3.52, 12])
    func aboveFullScaleIsClampedVisuallyOnly(level: Float) throws {
        let model = try flatModel(columns: 2, bands: 2, level: level)
        let buffer = try #require(SpectrogramRaster.buffer(for: model))

        #expect((pixel(buffer, column: 0, row: 0).r, pixel(buffer, column: 0, row: 0).g, pixel(buffer, column: 0, row: 0).b)
            == expectedPixel(for: 0), "a level above full scale was not drawn at the top of the ramp")
        // The model still holds what was measured.
        #expect(model.values.allSatisfy { $0 == level })
        #expect(try #require(model.value(column: 0, band: 0)) == level)
    }

    @Test("every pixel is fully opaque")
    func everyPixelIsOpaque() throws {
        let model = try gradientModel(columns: 9, bands: 5)
        let buffer = try #require(SpectrogramRaster.buffer(for: model))
        for index in stride(from: 3, to: buffer.pixels.count, by: 4) {
            #expect(buffer.pixels[index] == 255)
        }
    }

    // MARK: Degenerate and hostile inputs

    /// A model with no columns is an ordinary outcome — a file shorter than one analysis window — and
    /// there is nothing to rasterise. The caller says so in words instead.
    @Test("a model with no columns yields no buffer and no image")
    func anEmptyModelYieldsNothing() throws {
        let empty = try #require(Spectrogram.empty(sampleRate: 44_100, channelCount: 1))
        #expect(SpectrogramRaster.buffer(for: empty) == nil)
        #expect(SpectrogramRaster.image(for: empty) == nil)
    }

    /// The largest model production can produce still allocates a bounded buffer: 1024 × 512 × 4 bytes.
    @Test("the production grid produces exactly two mebibytes")
    func theProductionGridIsBounded() throws {
        let model = try gradientModel(
            columns: SpectrogramGridMapping.defaultMaximumColumnCount,
            bands: SpectrogramGridMapping.defaultMaximumBandCount
        )
        let buffer = try #require(SpectrogramRaster.buffer(for: model))
        #expect(buffer.pixels.count == 1_024 * 512 * 4)
        #expect(buffer.pixels.count == 2 * 1_024 * 1_024)
    }

    // MARK: Determinism, and independence from the view

    @Test("the same model always produces the same bytes")
    func theBufferIsDeterministic() throws {
        let model = try gradientModel(columns: 64, bands: 32)
        let first = try #require(SpectrogramRaster.buffer(for: model))
        let second = try #require(SpectrogramRaster.buffer(for: model))
        #expect(first == second)
    }

    /// **The guarantee that makes a resize free, and it is structural rather than measured.**
    ///
    /// `SpectrogramRaster.buffer(for:)` takes a `Spectrogram` and nothing else — no size, no scale, no
    /// geometry — so there is no expression a resize could change. This test states the consequence:
    /// two models that are equal produce identical bytes, whatever else is going on. The view holds the
    /// result in state keyed on the model, so a size change cannot re-enter this function at all.
    @Test("the buffer depends on the model alone")
    func theBufferDependsOnTheModelAlone() throws {
        let model = try gradientModel(columns: 128, bands: 64)
        let copy = try gradientModel(columns: 128, bands: 64)
        #expect(model == copy)

        let a = try #require(SpectrogramRaster.buffer(for: model))
        let b = try #require(SpectrogramRaster.buffer(for: copy))
        #expect(a == b)
    }

    /// Two models that differ anywhere produce different bytes, so the state key cannot collapse two
    /// files into one drawing.
    @Test("a different model produces different bytes")
    func differentModelsDiffer() throws {
        let quiet = try flatModel(columns: 8, bands: 8, level: -100)
        let loud = try flatModel(columns: 8, bands: 8, level: -20)
        let a = try #require(SpectrogramRaster.buffer(for: quiet))
        let b = try #require(SpectrogramRaster.buffer(for: loud))
        #expect(a != b)
    }

    /// The image is built from the buffer, so the two can never disagree about the layout.
    @Test("the image carries the buffer's own bytes")
    func theImageCarriesTheBuffer() throws {
        let model = try gradientModel(columns: 16, bands: 8)
        let buffer = try #require(SpectrogramRaster.buffer(for: model))
        let image = try #require(SpectrogramRaster.image(from: buffer))

        #expect(image.width == buffer.width)
        #expect(image.height == buffer.height)
        #expect(image.bytesPerRow == buffer.bytesPerRow)
        #expect(image.bitsPerPixel == 32)
        // The flag that keeps scaling honest: no level between two measured ones is ever invented.
        #expect(image.shouldInterpolate == false)
    }
}
