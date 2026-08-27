import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// Group 9's third subject: **B — the rasters, which are the larger number.**
//
// ADR-0025 records why they are counted apart from the models: *"Drawing a spectrogram builds an RGBA8
// image at the model's own size — 1024 × 512 × 4 = 2 MiB — held while it is on screen. A second drawn
// spectrogram adds another."* A raster is not a model: it is four bytes per cell rather than four, it
// lives for as long as a view is on screen rather than for as long as a comparison is open, and it is
// rebuilt from the model rather than retained beside it. Adding the two figures together would
// describe a state the app is never in.
//
// Task 9.4 asks for the **maximum**, *"asserted rather than assumed"*. The temptation is to reason
// from group 6 — paired replaces single, so two lanes, so two rasters — and write the conclusion down.
// That is the assumption the task refuses. What is asserted here instead is the count over **every**
// state the surface can be in, derived from the value that decides it.
//
// ## The level this is guaranteed at, stated plainly
//
// `ReportVisuals` is the whole of the app's answer to *which drawings are on screen*: `ReportView`
// renders `spectrogramSections` and nothing else, and each section builds its rasters from the models
// it carries. The bound asserted here is therefore a bound on **what this architecture asks to be
// drawn**. It is not a claim about SwiftUI's internals — a framework may hold a previous frame's
// image while it diffs, and nothing here can see that or promises otherwise.

@Suite("Cost — how many spectrogram rasters the surface can ask for")
struct PairedSpectrogramRasterCostTests {

    // MARK: - Fixtures

    private func model(rate: Double, columns: Int = 4, bands: Int = 2) -> Spectrogram {
        Spectrogram(
            values: [Float](repeating: -40, count: columns * bands),
            columnCount: columns, bandCount: bands,
            sampleRate: rate, frameCount: 4_096, channelCount: 1
        )!
    }

    private func stream(_ rate: Double) -> PCMStreamDescription {
        PCMStreamDescription(sampleRate: rate, channelCount: 1, frameCount: 4_096)!
    }

    private func paired(
        first: PairedSpectrogramLane, second: PairedSpectrogramLane
    ) -> PairedVisualsPresentation {
        PairedVisualsPresentation(
            waveform: PairedWaveformPresentation(
                axis: PairedWaveformAxis(first: stream(44_100), second: stream(48_000)),
                first: .absent, second: .absent
            ),
            spectrogram: PairedSpectrogramPresentation(
                axes: PairedSpectrogramAxes(first: stream(44_100), second: stream(48_000)),
                first: first, second: second
            )
        )
    }

    /// Every lane a paired spectrogram can be in — the three settled answers, plus the empty model
    /// that is an answer and not an absence.
    private var everyLane: [PairedSpectrogramLane] {
        [
            .model(model(rate: 44_100)),
            .model(model(rate: 44_100, columns: 0, bands: 0)),
            .absent,
            .failed(message: "Producing it did not succeed."),
        ]
    }

    /// Every state a single spectrogram can be in.
    private var everySinglePresentation: [SpectrogramPresentation] {
        [
            .loading,
            .model(model(rate: 44_100)),
            .model(model(rate: 44_100, columns: 0, bands: 0)),
            .absent,
            .failed(message: "Producing it did not succeed."),
        ]
    }

    /// **The counter under test.** How many rasters this state would have the surface build — a
    /// raster per model that `SpectrogramRaster` will actually produce a buffer for, which is what
    /// the views ask it for and what it refuses for a model with no cells.
    private func rastersAskedFor(by visuals: ReportVisuals) -> Int {
        visuals.spectrogramSections.reduce(0) { total, section in
            switch section {
            case let .singleSpectrogram(presentation):
                guard case let .model(model) = presentation else { return total }
                return total + (SpectrogramRaster.buffer(for: model) == nil ? 0 : 1)
            case let .pairedSpectrogram(presentation):
                return total + [presentation.first, presentation.second].reduce(0) { lanes, lane in
                    guard case let .model(model) = lane else { return lanes }
                    return lanes + (SpectrogramRaster.buffer(for: model) == nil ? 0 : 1)
                }
            case .singleWaveform, .pairedWaveform:
                return total
            }
        }
    }

    // MARK: - 9.4 · the maximum, over every state there is

    /// **Two, and never three.** Every combination of paired lanes, and every single-file state, is
    /// enumerated and counted — the bound is read off the states rather than argued from the design.
    @Test("no state of the surface asks for more than two spectrogram rasters")
    func neverMoreThanTwo() {
        var seen: [Int] = []

        for first in everyLane {
            for second in everyLane {
                let count = rastersAskedFor(by: .paired(paired(first: first, second: second)))
                seen.append(count)
                #expect(count <= 2)
            }
        }
        for presentation in everySinglePresentation {
            let count = rastersAskedFor(by: .single(waveform: .loading, spectrogram: presentation))
            seen.append(count)
            // A single-file surface asks for one at most — the other half of group 6's replacement.
            #expect(count <= 1)
        }

        // The bound is reached, so `<= 2` is a maximum rather than a statement about a surface that
        // never draws anything.
        #expect(seen.max() == 2)
        #expect(seen.contains(0))
        #expect(seen.contains(1))
    }

    /// **A pair replaces the singles; it is never added to them.** The section counts are what make
    /// the raster bound true, so they are asserted here too rather than borrowed from group 6: one
    /// spectral section, always, whichever mode the surface is in.
    @Test("the surface presents exactly one spectral section in either mode")
    func oneSectionEitherWay() {
        let single = ReportVisuals.single(waveform: .loading, spectrogram: .model(model(rate: 44_100)))
        let pair = ReportVisuals.paired(paired(
            first: .model(model(rate: 44_100)), second: .model(model(rate: 48_000))
        ))

        #expect(single.spectrogramSections.count == 1)
        #expect(pair.spectrogramSections.count == 1)
        // And a single section can carry two lanes, which is where the two comes from.
        #expect(rastersAskedFor(by: pair) == 2)
        #expect(rastersAskedFor(by: single) == 1)
    }

    // MARK: - 9.4 · B, what a raster costs, measured on the buffer itself

    /// **The size of the thing being bounded.** Not the model's 4 bytes per cell but the raster's
    /// four bytes per *pixel*, read off the buffer production would build at production's own caps.
    @Test("a production-sized raster is four bytes a cell, and two of them are twice that")
    func aRasterIsFourBytesACell() {
        let columns = SpectrogramGridMapping.defaultMaximumColumnCount
        let bands = SpectrogramGridMapping.defaultMaximumBandCount
        let productionModel = Spectrogram(
            values: [Float](repeating: -40, count: columns * bands),
            columnCount: columns, bandCount: bands,
            sampleRate: 44_100, frameCount: 1_048_576, channelCount: 2
        )!

        guard let buffer = SpectrogramRaster.buffer(for: productionModel) else {
            Issue.record("a production-sized model must produce a raster"); return
        }

        let rasterBytes = buffer.pixels.count
        let modelBytes = productionModel.values.count * MemoryLayout<Float>.stride

        print("""

        ── 9.4 · B — the raster, exact (RGBA8 buffer at the production caps) ──
        \(MeasurementConditions.description)
        model grid:            \(columns) × \(bands)
        one raster:            \(MiB.text(rasterBytes))
        two rasters (maximum): \(MiB.text(2 * rasterBytes))
        one model, for scale:  \(MiB.text(modelBytes))

        """)

        #expect(rasterBytes == columns * bands * SpectrogramRaster.bytesPerPixel)
        // Four bytes a cell against the model's four — the same number here only because a `Float`
        // and an RGBA8 pixel happen to be the same width, which is worth reading rather than assuming.
        #expect(rasterBytes == modelBytes)
        #expect(buffer.width == columns)
        #expect(buffer.height == bands)
    }

    /// **A model with no cells asks for no raster.** The reason the bound above is a bound on drawn
    /// lanes rather than on lanes: an empty model is a complete answer that is stated in words.
    @Test("a model with no cells produces no raster at all")
    func anEmptyModelProducesNothing() {
        let empty = model(rate: 44_100, columns: 0, bands: 0)
        #expect(SpectrogramRaster.buffer(for: empty) == nil)
        #expect(rastersAskedFor(by: .paired(paired(first: .model(empty), second: .model(empty)))) == 0)
    }
}
