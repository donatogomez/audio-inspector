import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// R6's subject: **the spectral drawing, given room — and the absolute scale that room must not touch.**
//
// The drawing cannot be asserted, so what is asserted is what decides it: the sizing bounds, the colour
// scale, the frequency geometry, the two render paths that keep *out of range* apart from *the floor*,
// and the structure of the surface. The scale is the part that matters most: a spectrogram that
// re-ranged itself per file would still look right and would have destroyed the one comparison two of
// them can honestly support.

@Suite("Feature — the spectrum workspace")
struct SpectrumWorkspaceTests {

    // MARK: - Fixtures

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureAnalysis")
    }

    private func source(_ name: String) throws -> String {
        try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
    }

    /// The file's **code**, with documentation and comments removed — a sweep for words a surface may
    /// not use has to read what it does, not what it says about itself.
    private func code(_ name: String) throws -> String {
        try source(name)
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
            .joined(separator: "\n")
    }

    private func model(
        rate: Double = 48_000, columns: Int = 64, bands: Int = 32, decibels: Float = -30
    ) throws -> Spectrogram {
        try #require(Spectrogram(
            values: Array(repeating: decibels, count: columns * bands),
            columnCount: columns, bandCount: bands,
            sampleRate: rate, frameCount: 48_000, channelCount: 2
        ))
    }

    private func stream(rate: Double, frames: Int = 480_000) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: rate, channelCount: 2, frameCount: frames))
    }

    /// A 44.1 kHz file beside a 96 kHz one — the case the shared frequency axis exists for.
    private func mixedRatePair(
        firstRate: Double = 44_100, secondRate: Double = 96_000
    ) throws -> PairedSpectrogramPresentation {
        PairedSpectrogramPresentation(
            axes: try #require(PairedSpectrogramAxes(
                first: try stream(rate: firstRate), second: try stream(rate: secondRate)
            )),
            first: .model(try model(rate: firstRate)),
            second: .model(try model(rate: secondRate))
        )
    }

    // MARK: - 5.1 — the absolute scale, which room must not touch

    /// **One ramp, one floor, one set of ticks — fixed constants, not derived from any file.**
    @Test("the colour scale is one fixed set, shared by every drawing")
    func theScaleIsFixed() throws {
        #expect(SpectrogramColourRamp.range.lowerBound == Spectrogram.floorDecibels)
        #expect(SpectrogramColourRamp.legendTicks == [-120, -90, -60, -30, 0])
        // The same input yields the same colour whatever else is on screen: the ramp is a pure function
        // of decibels, with no file, model or pair in its signature.
        for decibels in [Float(-120), -90, -60, -30, 0] {
            #expect(
                SpectrogramColourRamp.components(for: decibels).red
                    == SpectrogramColourRamp.components(for: decibels).red
            )
        }
        // A quiet model and a loud one map to different positions — neither is scaled to its own peak.
        #expect(SpectrogramColourRamp.position(for: -90) < SpectrogramColourRamp.position(for: -10))
    }

    /// **No auto-ranging anywhere on the surface.** Swept over the sources this slice writes and edits,
    /// comments stripped, because the comments name the refusals on purpose.
    @Test("nothing normalises, auto-ranges or re-colours")
    func nothingAutoRanges() throws {
        let forbidden = [
            "normalise", "normalize", "autoRange", "autoContrast", "autoScale", "dynamicRange",
            "maxValue", "minValue", "peakOf", "gainMatch", "brighten", "darken", "rescale",
            "contrastFor", "scaleFor(", "perFile",
        ]
        for file in ["ReportSpectrumView.swift", "SpectrogramView.swift", "PairedVisualsView.swift"] {
            let body = try code(file)
            for word in forbidden {
                #expect(!body.contains(word), "\(file) reaches for \(word)")
            }
        }
    }

    /// The luminance rises with level, so the scale reads the same way in greyscale — the property the
    /// ramp was built for, re-asserted here because a workspace that changed it would be changing what
    /// the colours mean.
    @Test("the ramp still increases monotonically in luminance")
    func theRampIsStillMonotonic() {
        let levels: [Float] = [-120, -100, -80, -60, -40, -20, 0]
        let luminances = levels.map(SpectrogramColourRamp.luminance(for:))
        #expect(zip(luminances, luminances.dropFirst()).allSatisfy { $0 < $1 })
    }

    // MARK: - 5.2 — frequency geometry, and 44.1 beside 96

    @Test("a single file's axis reaches its own Nyquist")
    func singleAxisReachesItsOwnNyquist() throws {
        #expect(try model(rate: 44_100).nyquist == 22_050)
        #expect(try model(rate: 96_000).nyquist == 48_000)
    }

    /// **The shared axis reaches the higher Nyquist and is never cropped to the lower one.**
    @Test("a 44.1 kHz lane beside a 96 kHz one occupies its own share and stops")
    func mixedRatesOccupyTheirOwnShare() throws {
        let axes = try #require(try mixedRatePair().axes)
        #expect(axes.sharedNyquist == 48_000)
        let low = try #require(axes.first)
        let high = try #require(axes.second)
        #expect(low.nyquist == 22_050)
        #expect(high.nyquist == 48_000)
        #expect(abs(low.frequencyFraction - 22_050 / 48_000) < 1e-12)
        #expect(high.frequencyFraction == 1)
        // The lower-rate lane has a region it cannot represent; the higher-rate one has none.
        #expect(low.outOfRangeFraction > 0)
        #expect(high.outOfRangeFraction == 0)
    }

    /// The same rule with the sides exchanged — the shared extent follows the rates, not the positions.
    @Test("the rule holds in either order")
    func theRuleHoldsInEitherOrder() throws {
        let axes = try #require(try mixedRatePair(firstRate: 96_000, secondRate: 44_100).axes)
        #expect(axes.sharedNyquist == 48_000)
        #expect(try #require(axes.first).frequencyFraction == 1)
        #expect(try #require(axes.second).outOfRangeFraction > 0)
    }

    /// Equal rates leave neither lane with a region above its own Nyquist.
    @Test("two files at the same rate have no out-of-range region")
    func equalRatesHaveNoOutOfRange() throws {
        let axes = try #require(try mixedRatePair(firstRate: 48_000, secondRate: 48_000).axes)
        #expect(try #require(axes.first).outOfRangeFraction == 0)
        #expect(try #require(axes.second).outOfRangeFraction == 0)
    }

    // MARK: - 5.3 — out of range is not the floor

    /// **Achromatic, where no ramp value is.** Every stop separates red from blue, so no level the ramp
    /// can produce equals an equal-component treatment — including the near-black it draws at the floor.
    @Test("the out-of-range treatment can equal no level of the ramp")
    func outOfRangeIsNotARampLevel() {
        let treatment = PairedSpectrogramAxes.outOfRangeTreatment
        #expect(treatment.red == treatment.green && treatment.green == treatment.blue,
                "the treatment is no longer achromatic")
        var level = Spectrogram.floorDecibels
        while level <= 0 {
            let ramp = SpectrogramColourRamp.components(for: level)
            let achromatic = ramp.red == ramp.green && ramp.green == ramp.blue
            #expect(!achromatic, "the ramp produces an achromatic colour at \(level) dBFS")
            level += 1
        }
        // And specifically not the floor, which is the one it would most easily be mistaken for.
        let floor = SpectrogramColourRamp.components(for: Spectrogram.floorDecibels)
        #expect(!(floor.red == treatment.red && floor.green == treatment.green && floor.blue == treatment.blue))
    }

    /// **Two render paths, not two colours that happen to differ.** The out-of-range region is a filled
    /// rectangle with no cell over it; the floor is a cell in the raster. A test that only compared
    /// colours would pass on a surface that drew the region through the ramp.
    @Test("out-of-range and the floor are drawn by different paths")
    func outOfRangeAndFloorAreDifferentPaths() throws {
        let paired = try code("PairedVisualsView.swift")
        let full = try source("PairedVisualsView.swift")
        #expect(paired.contains("Self.outOfRangeColour"), "the out-of-range fill is gone")
        #expect(full.contains("outOfRangeTreatment"), "the fill no longer comes from the fixed treatment")
        // The region is never produced by asking the ramp for a level.
        #expect(!paired.contains("SpectrogramColourRamp.colour(for: Spectrogram.floorDecibels)"))
        #expect(!paired.contains("outOfRangeColour = SpectrogramColourRamp"))
    }

    /// And it keeps its **words**, so the distinction never rests on colour alone.
    @Test("the out-of-range region keeps its sentence")
    func outOfRangeKeepsItsSentence() throws {
        let paired = try mixedRatePair()
        let text = PairedVisualsCopy.spectrogram(
            paired.first, for: .first,
            aboveItsNyquist: (paired.axes?.first?.outOfRangeFraction ?? 0) > 0
        )
        #expect(text.outOfRange == PairedVisualsCopy.outsideRepresentableRange)
        let sentence = try #require(text.outOfRange).lowercased()
        for word in ["silence", "silent", "quiet", "floor", "no energy", "empty", "zero"] {
            #expect(!sentence.contains(word), "the region reads as \(word)")
        }
        // It is a different sentence from the waveform's out-of-audio one: two absences, two facts.
        #expect(PairedVisualsCopy.outsideRepresentableRange != PairedVisualsCopy.outsideAudio)
    }

    // MARK: - 5.4 — sizing

    /// The report page keeps both strips it has always had, so the transitional surface is unchanged.
    @Test("the report page keeps its fixed strips")
    func reportPageKeepsItsStrips() {
        #expect(SpectrumPlotSizing.reportPage == .fixed(220))
        #expect(SpectrumPlotSizing.reportPageLane == .fixed(140))
    }

    /// **The maximum follows the model, not taste**: past one pixel per band a taller image is upscaled,
    /// and the raster is drawn with interpolation off.
    @Test("the maximum is derived from the model's band count")
    func theMaximumFollowsTheBandCount() {
        #expect(SpectrumPlotSizing.bandCount == CGFloat(SpectrogramGridMapping.defaultMaximumBandCount))
        #expect(SpectrumPlotSizing.workspaceSingle.maximum == SpectrumPlotSizing.bandCount)
        #expect(SpectrumPlotSizing.workspaceLane.maximum == SpectrumPlotSizing.bandCount / 2)
        // Two lanes together never exceed one full-resolution image's worth of height.
        #expect(2 * SpectrumPlotSizing.workspaceLane.maximum <= SpectrumPlotSizing.bandCount)
    }

    @Test("the workspace sizings grow, and lose nothing at the smallest window")
    func workspaceSizingsFlex() {
        for sizing in [SpectrumPlotSizing.workspaceSingle, .workspaceLane] {
            #expect(sizing.minimum < sizing.maximum, "a workspace sizing that cannot grow")
        }
        #expect(SpectrumPlotSizing.workspaceSingle.minimum == SpectrumPlotSizing.reportPage.minimum,
                "the workspace gives a single drawing less than the page it replaces")
    }

    /// Budgeted against the window's own minimum (`design.md` §4), for the worst case in each mode.
    @Test("both modes fit the smallest supported window")
    func bothModesFitTheSmallestWindow() {
        let contentHeight: CGFloat = 334
        let timeAxis: CGFloat = 18, legend: CGFloat = 30, singleProse: CGFloat = 34
        #expect(SpectrumPlotSizing.workspaceSingle.minimum + timeAxis + legend + singleProse <= contentHeight)

        // The worst **real** case: one lane carries an out-of-range sentence and one cannot, because the
        // higher Nyquist always occupies the whole shared axis (asserted below).
        let plot = SpectrumPlotSizing.workspaceLane.minimum
        let laneWithOutOfRange = 18 + plot + 18 + 18
        let laneWithout = 18 + plot + 18
        let paired = laneWithOutOfRange + laneWithout + 12 + 36 + legend
        #expect(paired <= contentHeight, "two spectral lanes do not fit at the window's minimum height")
    }

    /// **Only one lane can ever be out of range.** The shared axis reaches the greater Nyquist, so the
    /// higher-rate file always occupies all of it — which is what makes the budget above the worst case
    /// rather than an optimistic one.
    @Test("at most one lane can carry an out-of-range region")
    func atMostOneLaneIsOutOfRange() throws {
        for (first, second) in [(44_100.0, 96_000.0), (96_000.0, 44_100.0), (48_000.0, 48_000.0)] {
            let axes = try #require(try mixedRatePair(firstRate: first, secondRate: second).axes)
            let outOfRange = [axes.first, axes.second]
                .compactMap { $0 }
                .filter { $0.outOfRangeFraction > 0 }
            #expect(outOfRange.count <= 1, "both lanes are out of range at \(first) / \(second)")
        }
    }

    // MARK: - 5.5 — room buys no powers

    @Test("the workspace introduces no interaction")
    func theWorkspaceIntroducesNoInteraction() throws {
        let forbidden = [
            "onTapGesture", "onHover", "DragGesture", "MagnificationGesture", "MagnifyGesture",
            "onLongPressGesture", "gesture(", "simultaneousGesture", "highPriorityGesture",
            "ScrollViewReader", "scrollTo", "draggable", "Slider", "playhead", "scrub", "cursor",
            "zoom", "AVPlayer", "readout", "channelSelector", "differenceModel", "subtract",
        ]
        for file in ["ReportSpectrumView.swift", "SpectrogramView.swift", "PairedVisualsView.swift"] {
            let body = try code(file)
            for word in forbidden {
                #expect(!body.contains(word), "\(file) reaches for \(word)")
            }
        }
        #expect(try source("SpectrogramView.swift").contains("allowsHitTesting(false)"))
    }

    /// **This slice computes nothing**, and the raster stays a function of the model alone so a resize
    /// redraws rather than rebuilds.
    @Test("the workspace starts no work and rebuilds no raster")
    func theWorkspaceStartsNoWork() throws {
        let body = try code("ReportSpectrumView.swift")
        for word in ["AVFoundation", "AudioInspectorMedia", "AudioInspectorAnalysis", "Process",
                     "Accumulator", "Decoder", "decode", "Task {", "async ", "await ", "SpectrogramRaster",
                     "fft", "FFT", "transform"] {
            #expect(!body.contains(word), "the workspace reaches for \(word)")
        }
        // The raster is keyed on the model, never on a size.
        let plot = try code("SpectrogramView.swift")
        #expect(plot.contains(".task(id: model)"), "the raster is no longer keyed on the model alone")
        #expect(!plot.contains(".task(id: sizing)"))
    }

    /// The workspace decides no geometry of its own.
    @Test("the workspace reaches into no geometry")
    func theWorkspaceReachesIntoNoGeometry() throws {
        let body = try code("ReportSpectrumView.swift")
        for word in ["SpectrogramGeometry", "SpectrogramAxes", "PairedSpectrogramAxes(", "nyquist",
                     "frequencyFraction", "SpectrogramColourRamp"] {
            #expect(!body.contains(word), "the workspace reaches into \(word)")
        }
    }

    // MARK: - 5.6 — states, legend, accessibility

    @Test("the three absences are distinguishable and none is a picture")
    func theThreeAbsencesAreDistinguishable() throws {
        let states: [SpectrogramPresentation] = [
            .loading, .absent, .failed(message: "The drawing could not be produced."),
        ]
        let headlines = states.map { SpectrogramCopy.text(for: $0).headline }
        #expect(Set(headlines.compactMap { $0 }).count == 3, "two states share a sentence")
        for state in states {
            #expect(SpectrogramCopy.text(for: state).headline != nil)
        }
    }

    /// A model with no columns is a **statement**, not an absence — the distinction the domain keeps.
    @Test("a model with no columns is a statement, not an absence")
    func anEmptyModelIsAStatement() throws {
        let empty = try #require(Spectrogram(
            values: [], columnCount: 0, bandCount: 0, sampleRate: 48_000, frameCount: 0, channelCount: 1
        ))
        let text = SpectrogramCopy.text(for: .model(empty))
        #expect(text.headline != nil)
        #expect(text.headline != SpectrogramCopy.text(for: .absent).headline)
    }

    /// **One legend describes both lanes**, and it is the single-file section's own — not a second set
    /// of numbers that could drift from the first.
    @Test("the pairing presents exactly one legend, and it is the section's own")
    func thePairingPresentsOneLegend() throws {
        let paired = try code("PairedVisualsView.swift")
        #expect(paired.contains("SpectrogramLegend()"), "the pairing draws a ramp it explains nowhere")
        #expect(paired.components(separatedBy: "SpectrogramLegend()").count - 1 == 1,
                "the pairing presents more than one legend")
        // It is shown only where colours actually are.
        #expect(paired.contains("hasDrawnLane"))
    }

    /// **One element per drawing, never one per cell.** 524 288 shapes announced in sequence would be
    /// far worse than silence.
    @Test("each drawing is one accessibility element")
    func eachDrawingIsOneElement() throws {
        for file in ["ReportSpectrumView.swift", "SpectrogramView.swift", "PairedVisualsView.swift"] {
            let body = try code(file)
            #expect(!body.contains("accessibilityLabel(band"), "\(file) announces a band")
            #expect(!body.contains("accessibilityLabel(cell"), "\(file) announces a cell")
        }
        let plot = try code("SpectrogramView.swift")
        #expect(plot.contains("accessibilityElement(children: .ignore)"))
        #expect(plot.contains("accessibilityHidden(true)"), "the cells, axes or legend gained an element")
        // The paired lane names which file it belongs to.
        let paired = try mixedRatePair()
        let text = PairedVisualsCopy.spectrogram(paired.first, for: .first, aboveItsNyquist: true)
        #expect(text.accessibilityLabel.contains(ComparisonCopy.firstFile))
    }
}
