import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureAnalysis
@testable import FeatureImport

// Group 6's subject: **which drawings the report surface presents, and how many.**
//
// The composition root is the only place that can see both a settled pair and the geometry that lays it
// out, so the choice is made there and asserted here as a value. Nothing is rendered: a `Canvas` cannot
// be asserted, which is why the surface's answer is a value in the first place.

@MainActor
@Suite("App — the report presents one file's drawings, or two")
struct ReportVisualsTests {

    // MARK: - Fixtures

    private func report(_ name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: 2_048, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(container: .available("wav")),
            warnings: [],
            status: .completed
        )
    }

    private func envelope(peak: Float) -> WaveformEnvelope {
        WaveformEnvelope(
            buckets: [WaveformBucket(minimum: -peak, maximum: peak)!], frameCount: 2_048, channelCount: 2
        )!
    }

    private func model(rate: Double, columns: Int = 1) -> Spectrogram {
        Spectrogram(
            values: Array(repeating: Float(-30), count: columns * 2), columnCount: columns, bandCount: columns > 0 ? 2 : 0,
            sampleRate: rate, frameCount: 2_048, channelCount: 2
        )!
    }

    private func stream(rate: Double, seconds: Double) -> PCMStreamDescription {
        PCMStreamDescription(sampleRate: rate, channelCount: 2, frameCount: Int(rate * seconds))!
    }

    private func visuals(
        peak: Float, rate: Double, seconds: Double,
        waveform: SettledWaveform? = nil, spectrogram: SettledSpectrogram? = nil,
        stream withStream: PCMStreamDescription?? = nil
    ) -> FileVisuals {
        FileVisuals(
            waveform: waveform ?? .available(envelope(peak: peak)),
            spectrogram: spectrogram ?? .available(model(rate: rate)),
            stream: withStream ?? stream(rate: rate, seconds: seconds)
        )!
    }

    private func presentation(
        waveform: WaveformState = .available(WaveformEnvelope(buckets: [], frameCount: 0, channelCount: 2)!),
        spectrogram: SpectrogramState = .unavailable
    ) -> InspectionPresentation {
        InspectionPresentation(report: report("a.wav"), waveform: waveform, spectrogram: spectrogram)
    }

    private func ready(_ paired: PairedVisuals?) -> ImportFlowModel.ComparisonState {
        .ready(FileComparison(first: report("a.wav"), second: report("b.wav")), nil, paired)
    }

    private let pair = { () -> PairedVisuals in
        let first = FileVisuals(
            waveform: .available(WaveformEnvelope(
                buckets: [WaveformBucket(minimum: -0.25, maximum: 0.25)!], frameCount: 2_048, channelCount: 2
            )!),
            spectrogram: .available(Spectrogram(
                values: [-30, -40], columnCount: 1, bandCount: 2,
                sampleRate: 44_100, frameCount: 2_048, channelCount: 2
            )!),
            stream: PCMStreamDescription(sampleRate: 44_100, channelCount: 2, frameCount: 88_200)!
        )!
        let second = FileVisuals(
            waveform: .available(WaveformEnvelope(
                buckets: [WaveformBucket(minimum: -0.75, maximum: 0.75)!], frameCount: 4_096, channelCount: 2
            )!),
            spectrogram: .available(Spectrogram(
                values: [-10, -20], columnCount: 1, bandCount: 2,
                sampleRate: 96_000, frameCount: 4_096, channelCount: 2
            )!),
            stream: PCMStreamDescription(sampleRate: 96_000, channelCount: 2, frameCount: 384_000)!
        )!
        return PairedVisuals(first: first, second: second)
    }()

    // MARK: - 6.1 — no settled pair means the first file's own drawings

    /// One rule covers *not yet*, cancelled, dismissed, superseded and *the second file failed to open*,
    /// because all five arrive as a comparison state carrying no settled pair.
    @Test("every state without a settled pair presents the single drawings")
    func withoutAPairTheSinglesStand() {
        let states: [ImportFlowModel.ComparisonState] = [
            .none,
            .loading,
            .failed(message: "That file could not be opened for comparison."),
            ready(nil),
        ]
        for state in states {
            let visuals = RootView.reportVisuals(for: presentation(), in: state)
            guard case .single = visuals else {
                Issue.record("\(state) presented \(visuals) instead of the single drawings"); return
            }
            #expect(visuals.waveformSections.count == 1)
            #expect(visuals.spectrogramSections.count == 1)
            guard case .singleWaveform = visuals.waveformSections[0],
                  case .singleSpectrogram = visuals.spectrogramSections[0]
            else {
                Issue.record("\(state) did not present the first file's own drawings"); return
            }
        }
    }

    // MARK: - 6.2 / 6.3 — a settled pair stands in for them, exactly once

    @Test("a settled pair presents the paired drawings, and the single ones are not presented")
    func aPairStandsIn() {
        let visuals = RootView.reportVisuals(for: presentation(), in: ready(pair))
        guard case .paired = visuals else {
            Issue.record("a settled pair presented \(visuals)"); return
        }
        guard case .pairedWaveform = visuals.waveformSections[0],
              case .pairedSpectrogram = visuals.spectrogramSections[0]
        else {
            Issue.record("the paired sections were not presented"); return
        }
        // And the single sections are nowhere on the surface.
        #expect(!visuals.waveformSections.contains { if case .singleWaveform = $0 { true } else { false } })
        #expect(!visuals.spectrogramSections.contains { if case .singleSpectrogram = $0 { true } else { false } })
    }

    /// **The property the product decision exists for.** The first file's envelope is on screen once,
    /// and its spectral model once — never twice, at two different geometries.
    @Test("the first file's drawings appear exactly once, in either mode")
    func exactlyOnce() {
        for state in [ImportFlowModel.ComparisonState.none, ready(nil), ready(pair)] {
            let visuals = RootView.reportVisuals(for: presentation(), in: state)
            #expect(visuals.waveformSections.count == 1, "\(state) presented \(visuals.waveformSections.count) waveforms")
            #expect(visuals.spectrogramSections.count == 1, "\(state) presented \(visuals.spectrogramSections.count) spectrograms")
        }
    }

    /// The two sections read the **same** value, so a paired waveform beside a single spectrogram is not
    /// something this surface can produce.
    @Test("the two visual sections always agree about which mode the surface is in")
    func bothSectionsAgree() {
        for state in [ImportFlowModel.ComparisonState.none, .loading, ready(nil), ready(pair)] {
            let visuals = RootView.reportVisuals(for: presentation(), in: state)
            let waveformIsPaired = { if case .pairedWaveform = visuals.waveformSections[0] { true } else { false } }()
            let spectrogramIsPaired = { if case .pairedSpectrogram = visuals.spectrogramSections[0] { true } else { false } }()
            #expect(waveformIsPaired == spectrogramIsPaired, "\(state) mixed the two modes")
        }
    }

    // MARK: - The mapping is total, and the geometry is not recomputed

    /// The axes come from the types that own those rules, built from the descriptions the pair carries.
    /// Asserted against those types directly, so a third formula in this layer would disagree.
    @Test("the paired presentation carries the geometry those types produce, and not a copy of the rule")
    func geometryComesFromTheAxisTypes() {
        guard case let .paired(paired) = RootView.reportVisuals(for: presentation(), in: ready(pair)) else {
            Issue.record("no paired presentation"); return
        }
        let expectedTime = PairedWaveformAxis(first: pair.first.stream, second: pair.second.stream)
        let expectedAxes = PairedSpectrogramAxes(first: pair.first.stream, second: pair.second.stream)
        #expect(paired.waveform.axis == expectedTime)
        #expect(paired.spectrogram.axes == expectedAxes)
        // And they say what group 4 and group 5 say: 2 s against 4 s, 22.05 kHz against 48 kHz.
        #expect(paired.waveform.axis?.first?.fraction == 0.5)
        #expect(paired.spectrogram.axes?.sharedNyquist == 48_000)
        #expect(paired.spectrogram.axes?.first?.frequencyFraction == 22_050.0 / 48_000.0)
    }

    // MARK: - 6.5 — nothing else on the report changes

    /// The comparison the surface is handed is the same value whichever drawings are on screen: the
    /// visual mode reads the state, it does not rewrite it.
    @Test("the technical and measurement comparison are unchanged by the visual mode")
    func theComparisonIsUnchanged() {
        let technical = FileComparison(first: report("a.wav"), second: report("b.wav"))
        let withPair = ImportFlowModel.ComparisonState.ready(technical, nil, pair)
        let withoutPair = ImportFlowModel.ComparisonState.ready(technical, nil, nil)

        let a = RootView.comparisonPresentation(for: withPair)
        let b = RootView.comparisonPresentation(for: withoutPair)
        #expect(a == b, "the paired drawings changed the comparison beside them")
        guard case let .ready(shown, measurements) = a else {
            Issue.record("the comparison was not presented: \(a)"); return
        }
        #expect(shown == technical)
        #expect(measurements == nil)
    }

    /// And the report itself — the properties, the warnings, the status — is the same value the surface
    /// would have been handed without a pair.
    @Test("the report handed to the surface is untouched by the visual mode")
    func theReportIsUntouched() {
        let state = presentation()
        let before = state.report
        _ = RootView.reportVisuals(for: state, in: ready(pair))
        #expect(state.report == before, "the visual mode rewrote the report")
        #expect(state.report.properties.container == .available("wav"))
        #expect(state.report.warnings.isEmpty)
        #expect(state.report.status == .completed)
    }

    // MARK: - Absence and failure stay in the pair

    /// **No silent fallback.** A side with nothing to draw is still a side of the pair, and says so in
    /// its own lane — it does not send the surface back to one file's drawing.
    @Test("an absent or failed side keeps the paired presentation")
    func absenceStaysInThePair() {
        let cases: [(SettledWaveform, SettledSpectrogram, PairedWaveformLane, PairedSpectrogramLane)] = [
            (.unavailable, .unavailable, .absent, .absent),
            (.failed(message: "no envelope"), .failed(message: "no model"),
             .failed(message: "no envelope"), .failed(message: "no model")),
        ]
        for (settledWaveform, settledSpectrogram, expectedWaveform, expectedSpectrogram) in cases {
            let side = visuals(peak: 0, rate: 44_100, seconds: 2, waveform: settledWaveform, spectrogram: settledSpectrogram)
            let paired = PairedVisuals(first: side, second: visuals(peak: 0.5, rate: 96_000, seconds: 4))
            guard case let .paired(presented) = RootView.reportVisuals(for: presentation(), in: ready(paired)) else {
                Issue.record("an absent side fell back to the single drawings"); return
            }
            #expect(presented.waveform.first == expectedWaveform)
            #expect(presented.spectrogram.first == expectedSpectrogram)
            // The other side is untouched by its neighbour's absence.
            guard case .envelope = presented.waveform.second, case .model = presented.spectrogram.second else {
                Issue.record("the present side was withheld by the absent one"); return
            }
        }
    }

    /// A model with no columns is a complete answer, and reaches the lane as a model rather than as an
    /// absence — the distinction `SpectrogramCopyTests` exists to protect.
    @Test("a spectral model with no columns arrives as a model, not as an absence")
    func noColumnsIsStillAModel() {
        let short = Spectrogram.empty(sampleRate: 44_100, channelCount: 2)!
        let side = visuals(peak: 0.5, rate: 44_100, seconds: 2, spectrogram: .available(short))
        let paired = PairedVisuals(first: side, second: visuals(peak: 0.5, rate: 96_000, seconds: 4))
        guard case let .paired(presented) = RootView.reportVisuals(for: presentation(), in: ready(paired)) else {
            Issue.record("no paired presentation"); return
        }
        #expect(presented.spectrogram.first == .model(short))
        #expect(presented.spectrogram.first != .absent)
    }

    /// A pair whose reads reported no stream has no axis to lay anything out against — and is still a
    /// pair. Falling back to one file's drawing here would answer a question nobody asked.
    @Test("a pair with no axis is still a pair")
    func aPairWithNoAxisIsStillAPair() {
        let side = FileVisuals(waveform: .unavailable, spectrogram: .unavailable, stream: nil)!
        let paired = PairedVisuals(first: side, second: side)
        guard case let .paired(presented) = RootView.reportVisuals(for: presentation(), in: ready(paired)) else {
            Issue.record("a pair with no axis fell back to the single drawings"); return
        }
        #expect(presented.waveform.axis == nil)
        #expect(presented.spectrogram.axes == nil)
        #expect(presented.waveform.first == .absent)
    }

    // MARK: - The lane mappings are total and keep the three answers apart

    @Test("the three settled answers map to three lanes, and never to each other")
    func lanesAreTotal() {
        let produced = envelope(peak: 0.4)
        #expect(RootView.pairedWaveformLane(for: .available(produced)) == .envelope(produced))
        #expect(RootView.pairedWaveformLane(for: .unavailable) == .absent)
        #expect(RootView.pairedWaveformLane(for: .failed(message: "x")) == .failed(message: "x"))
        #expect(RootView.pairedWaveformLane(for: .unavailable) != RootView.pairedWaveformLane(for: .failed(message: "x")))

        let grid = model(rate: 48_000)
        #expect(RootView.pairedSpectrogramLane(for: .available(grid)) == .model(grid))
        #expect(RootView.pairedSpectrogramLane(for: .unavailable) == .absent)
        #expect(RootView.pairedSpectrogramLane(for: .failed(message: "y")) == .failed(message: "y"))
    }

    /// A paired lane cannot be *still being produced*: the pair exists only once both files have
    /// settled, and the type has no case for it.
    @Test("a paired lane widens to the single-file vocabulary without ever meaning loading")
    func lanesNeverMeanLoading() {
        for lane in [PairedWaveformLane.envelope(envelope(peak: 0.1)), .absent, .failed(message: "z")] {
            #expect(lane.asSingle != .loading)
        }
    }
}
