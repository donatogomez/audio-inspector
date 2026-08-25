import Testing

import AudioInspectorDomain
@testable import FeatureImport

// The contract of the settled visual shapes, and nothing else. No flow, no second read, no rendering:
// what is asserted is what survives the collapse from lifecycle to a settled answer, and what the types
// refuse to represent at all.

@Suite("Feature — settling a file's visual artefacts")
struct SettledVisualsTests {

    // MARK: - Fixtures

    private func envelope(peak: Float = 0.5) -> WaveformEnvelope {
        WaveformEnvelope(
            buckets: [WaveformBucket(minimum: -peak, maximum: peak)!],
            frameCount: 2_048,
            channelCount: 2
        )!
    }

    private func model(sampleRate: Double = 44_100) -> Spectrogram {
        Spectrogram(
            values: [-30, -40],
            columnCount: 1,
            bandCount: 2,
            sampleRate: sampleRate,
            frameCount: 2_048,
            channelCount: 2
        )!
    }

    /// A file shorter than one analysis window: real audio, no complete window, and a **complete
    /// answer** rather than an absence.
    private func modelWithNoColumns() -> Spectrogram {
        Spectrogram.empty(sampleRate: 44_100, channelCount: 2)!
    }

    private func stream(sampleRate: Double = 44_100, frameCount: Int = 2_048) -> PCMStreamDescription {
        PCMStreamDescription(sampleRate: sampleRate, channelCount: 2, frameCount: frameCount)!
    }

    private func analyses(
        waveform: WaveformOutcome,
        spectrogram: SpectrogramOutcome
    ) -> InspectionAnalyses {
        InspectionAnalyses(
            waveform: waveform,
            spectrogram: spectrogram,
            signalLevelMetrics: .unavailable,
            truePeak: .unavailable,
            loudness: .unavailable,
            significantBandwidth: .unavailable
        )
    }

    private func presentation(
        waveform: WaveformState,
        spectrogram: SpectrogramState
    ) -> InspectionPresentation {
        InspectionPresentation(
            report: InspectionReport(
                file: AudioFileReference(
                    displayName: "a.wav",
                    fileExtension: "wav",
                    sizeBytes: 2_048,
                    modifiedAt: nil,
                    source: .userSelectedLocalFile(displayName: "a.wav", locationDisclosure: .omitted)
                ),
                properties: TechnicalProperties(container: .available("wav")),
                warnings: [],
                status: .completed
            ),
            waveform: waveform,
            spectrogram: spectrogram
        )
    }

    // MARK: - The artefacts survive the collapse unchanged

    @Test("an available envelope is carried through exactly")
    func availableEnvelopeIsCarried() {
        let produced = envelope(peak: 0.75)
        let settled = analyses(waveform: .available(produced), spectrogram: .unavailable)
            .settledVisuals(from: stream())
        #expect(settled?.waveform == .available(produced))
    }

    @Test("an available spectral model is carried through exactly")
    func availableModelIsCarried() {
        let produced = model()
        let settled = analyses(waveform: .unavailable, spectrogram: .available(produced))
            .settledVisuals(from: stream())
        #expect(settled?.spectrogram == .available(produced))
    }

    /// The distinction `SpectrogramCopyTests` exists to protect: a model with no columns is a complete
    /// answer for a file shorter than one analysis window, and degrading it to an absence would lose it.
    @Test("a model with no columns stays available, and never becomes an absence")
    func noColumnsIsNotAnAbsence() {
        let short = modelWithNoColumns()
        let settled = analyses(waveform: .unavailable, spectrogram: .available(short))
            .settledVisuals(from: stream())
        #expect(settled?.spectrogram == .available(short))
        #expect(settled?.spectrogram != .unavailable)
    }

    // MARK: - Absence and failure stay apart

    @Test("an unavailable envelope stays unavailable")
    func unavailableEnvelopeStays() {
        let settled = analyses(waveform: .unavailable, spectrogram: .unavailable)
            .settledVisuals(from: stream())
        #expect(settled?.waveform == .unavailable)
    }

    @Test("a failed envelope stays failed, with its sentence")
    func failedEnvelopeStays() {
        let settled = analyses(waveform: .failed(message: "The samples could not be read."), spectrogram: .unavailable)
            .settledVisuals(from: stream())
        #expect(settled?.waveform == .failed(message: "The samples could not be read."))
    }

    @Test("an unavailable spectral model stays unavailable")
    func unavailableModelStays() {
        let settled = analyses(waveform: .unavailable, spectrogram: .unavailable)
            .settledVisuals(from: stream())
        #expect(settled?.spectrogram == .unavailable)
    }

    @Test("a failed spectral model stays failed, with its sentence")
    func failedModelStays() {
        let settled = analyses(waveform: .unavailable, spectrogram: .failed(message: "The transform did not complete."))
            .settledVisuals(from: stream())
        #expect(settled?.spectrogram == .failed(message: "The transform did not complete."))
    }

    /// The collapse the measurements make deliberately — failure and absence both to `nil` — is the one
    /// this must not make. A paired surface has to say which of the two happened.
    @Test("absence and failure are not interchangeable, for either artefact")
    func absenceAndFailureAreNotTheSame() {
        let absent = analyses(waveform: .unavailable, spectrogram: .unavailable)
            .settledVisuals(from: stream())
        let failed = analyses(
            waveform: .failed(message: "no"), spectrogram: .failed(message: "no")
        ).settledVisuals(from: stream())

        #expect(absent != failed)
        #expect(absent?.waveform != failed?.waveform)
        #expect(absent?.spectrogram != failed?.spectrogram)
    }

    // MARK: - The stream description

    @Test("the stream description is carried through exactly, and never rebuilt")
    func streamIsCarried() {
        let read = stream(sampleRate: 96_000, frameCount: 480_000)
        let settled = analyses(waveform: .available(envelope()), spectrogram: .available(model()))
            .settledVisuals(from: read)
        #expect(settled?.stream == read)
    }

    /// `AudioDecoding` reports no description exactly when the file exposed no usable frame count — and
    /// then every analysis is absent. An artefact that exists without one is a combination no read can
    /// produce, and the type refuses it rather than presenting a drawing whose axis cannot be stated.
    @Test("an artefact without a stream description is unrepresentable")
    func availableWithoutAStreamIsRefused() {
        #expect(FileVisuals(waveform: .available(envelope()), spectrogram: .unavailable, stream: nil) == nil)
        #expect(FileVisuals(waveform: .unavailable, spectrogram: .available(model()), stream: nil) == nil)
    }

    @Test("an absence without a stream description is an ordinary outcome")
    func absentWithoutAStreamIsFine() {
        let settled = FileVisuals(waveform: .unavailable, spectrogram: .unavailable, stream: nil)
        #expect(settled?.stream == nil)
        #expect(settled?.waveform == .unavailable)
    }

    // MARK: - What never reaches a settled value

    /// A drawing still being produced is a state of the flow, not a result. Publishing then would report
    /// a file's drawings as missing when they are a second away.
    @Test("loading never produces a settled value")
    func loadingNeverSettles() {
        #expect(presentation(waveform: .loading, spectrogram: .available(model()))
            .settledVisuals(from: stream()) == nil)
        #expect(presentation(waveform: .available(envelope()), spectrogram: .loading)
            .settledVisuals(from: stream()) == nil)
        #expect(presentation(waveform: .loading, spectrogram: .loading)
            .settledVisuals(from: stream()) == nil)
    }

    /// Cancellation belongs to an operation the user already replaced. Rendering it as an absence would
    /// blame the file for the user's own action — the refusal `WaveformState.init?(_:)` already makes.
    @Test("cancellation never produces a settled value, and never becomes an absence")
    func cancellationNeverSettles() {
        #expect(analyses(waveform: .cancelled, spectrogram: .cancelled)
            .settledVisuals(from: stream()) == nil)
        #expect(analyses(waveform: .cancelled, spectrogram: .available(model()))
            .settledVisuals(from: stream()) == nil)
        #expect(analyses(waveform: .available(envelope()), spectrogram: .cancelled)
            .settledVisuals(from: stream()) == nil)

        // The stronger statement: not merely "no pair", but never mistaken for the file having nothing.
        #expect(SettledWaveform(WaveformOutcome.cancelled) == nil)
        #expect(SettledSpectrogram(SpectrogramOutcome.cancelled) == nil)
    }

    // MARK: - The pair

    private func visuals(peak: Float, sampleRate: Double) -> FileVisuals {
        FileVisuals(
            waveform: .available(envelope(peak: peak)),
            spectrogram: .available(model(sampleRate: sampleRate)),
            stream: stream(sampleRate: sampleRate)
        )!
    }

    @Test("a pair keeps its two sides apart, by position")
    func theTwoSidesStayApart() {
        let a = visuals(peak: 0.25, sampleRate: 44_100)
        let b = visuals(peak: 0.75, sampleRate: 96_000)
        let pair = PairedVisuals(first: a, second: b)

        #expect(pair.first == a)
        #expect(pair.second == b)
        #expect(pair.first != pair.second)
        // Order is meaning: swapping the sides is a different pair, not the same one.
        #expect(pair != PairedVisuals(first: b, second: a))
    }

    @Test("a pair needs both sides settled, and yields nothing otherwise")
    func aPairNeedsBothSides() {
        let settled = visuals(peak: 0.5, sampleRate: 44_100)
        #expect(PairedVisuals(first: settled, second: nil) == nil)
        #expect(PairedVisuals(first: nil, second: settled) == nil)
        #expect(PairedVisuals(first: nil, second: nil) == nil)
        #expect(PairedVisuals(first: settled, second: settled) != nil)
    }

    /// The pair carries the two sides and **nothing else**: no verdict, no score, no similarity, no
    /// comparability, no operation token. A field for one is what this asserts cannot appear.
    @Test("a pair publishes no comparison outcome of any kind")
    func aPairPublishesNoOutcome() {
        let pair = PairedVisuals(first: visuals(peak: 0.25, sampleRate: 44_100),
                                 second: visuals(peak: 0.75, sampleRate: 96_000))
        let fields = Mirror(reflecting: pair).children.compactMap(\.label)
        #expect(fields == ["first", "second"])
    }

    /// A drawing never enters the `schemaVersion` 1 export, and nothing here may open a path to one.
    @Test("none of these types is Codable or Comparable")
    func nothingIsCodableOrComparable() {
        #expect(!(PairedVisuals.self is any Encodable.Type))
        #expect(!(PairedVisuals.self is any Decodable.Type))
        #expect(!(FileVisuals.self is any Encodable.Type))
        #expect(!(FileVisuals.self is any Decodable.Type))
        #expect(!(SettledWaveform.self is any Encodable.Type))
        #expect(!(SettledSpectrogram.self is any Encodable.Type))
        #expect(!(PairedVisuals.self is any Comparable.Type))
        #expect(!(FileVisuals.self is any Comparable.Type))
    }

    // MARK: - Both sides collapse the same way

    /// The first file's `…State` and the compared file's `…Outcome` are different types with the same
    /// three settled answers, and the two collapses must not drift apart.
    @Test("a state and an outcome describing the same thing settle identically")
    func bothSidesAgree() {
        let produced = envelope()
        let fromState = presentation(waveform: .available(produced), spectrogram: .unavailable)
            .settledVisuals(from: stream())
        let fromOutcome = analyses(waveform: .available(produced), spectrogram: .unavailable)
            .settledVisuals(from: stream())
        #expect(fromState == fromOutcome)
    }
}
