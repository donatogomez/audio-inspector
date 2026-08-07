import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureAnalysis
import FeatureImport
import Foundation
import Testing

// What the spectrogram section says, and — more importantly — what it must never say.

private func model(
    columns: Int = 4, bands: Int = 4, sampleRate: Double = 44_100,
    frameCount: Int = 44_100, channels: Int = 2
) throws -> Spectrogram {
    try #require(Spectrogram(
        values: [Float](repeating: -60, count: columns * bands),
        columnCount: columns, bandCount: bands,
        sampleRate: sampleRate, frameCount: frameCount, channelCount: channels
    ))
}

private func emptyModel(frameCount: Int = 1_000) throws -> Spectrogram {
    try #require(Spectrogram(
        values: [], columnCount: 0, bandCount: 0,
        sampleRate: 44_100, frameCount: frameCount, channelCount: 1
    ))
}

@Suite("Presentation — spectrogram states in words")
struct SpectrogramCopyTests {
    private func text(_ presentation: SpectrogramPresentation) -> SpectrogramSectionText {
        SpectrogramCopy.text(for: presentation)
    }

    /// Every state says something. An empty area would leave the reader to guess.
    @Test("each state produces its own words")
    func everyStateSpeaks() throws {
        let states: [SpectrogramPresentation] = [
            .loading, .model(try model()), .model(try emptyModel()), .absent,
            .failed(message: "The spectrogram for this file could not be produced."),
        ]
        let labels = states.map { text($0).accessibilityLabel }
        #expect(Set(labels).count == labels.count, "two states say the same thing: \(labels)")
        #expect(labels.allSatisfy { !$0.isEmpty })
    }

    /// A drawing is the content only when there is one; otherwise the fact is stated.
    @Test("a drawable model shows the drawing and names it, with no headline standing in for it")
    func aDrawableModelHasNoHeadline() throws {
        let shown = text(.model(try model()))
        #expect(shown.headline == nil, "a headline replaced a drawing that exists")
        #expect(shown.detail != nil)
    }

    /// The three that are **not** the same thing, and must never read as one another.
    @Test("absence, failure and too-short are three different statements")
    func theThreeNonDrawingStatesDiffer() throws {
        let absent = text(.absent).accessibilityLabel
        let failed = text(.failed(message: "It could not be produced.")).accessibilityLabel
        let tooShort = text(.model(try emptyModel())).accessibilityLabel

        #expect(absent != failed)
        #expect(absent != tooShort)
        #expect(failed != tooShort)
        #expect(tooShort.lowercased().contains("short"), "the too-short case does not explain itself")
    }

    /// Absence does not blame the file, and failure is about the drawing rather than the inspection.
    @Test("nothing says the file is at fault")
    func neitherStateBlamesTheFile() throws {
        let absent = text(.absent)
        #expect(absent.detail?.contains("Everything else in this report is unchanged") == true)

        let failed = text(.failed(message: "It could not be produced."))
        #expect(failed.detail?.contains("not something read from the audio") == true)
        #expect(failed.detail?.contains("Everything else in this report is unchanged") == true)
    }

    @Test("loading does not withhold anything")
    func loadingIsNeutral() {
        let loading = text(.loading)
        #expect(loading.headline?.contains("Preparing") == true)
        #expect(loading.accessibilityLabel.contains("…") == false, "an ellipsis would be read aloud")
    }
}

@Suite("Presentation — spectrogram accessibility")
struct SpectrogramAccessibilityTests {
    /// **One element, whatever the model's size.** A drawing cannot be read cell by cell, and the label
    /// must not grow with the grid.
    @Test("the label's length does not depend on the number of cells")
    func labelDoesNotGrowWithTheModel() throws {
        let tiny = SpectrogramCopy.text(for: .model(try model(columns: 1, bands: 1))).accessibilityLabel
        let huge = SpectrogramCopy.text(for: .model(try model(columns: 1_024, bands: 512))).accessibilityLabel
        #expect(tiny == huge, "the label changed between 1 cell and 524 288")
    }

    /// What the spoken description must carry, so a listener gets what the eye gets from the axes and
    /// the legend.
    @Test("the label states the range, the scale and the channels")
    func labelCarriesTheAxes() throws {
        let label = SpectrogramCopy.text(for: .model(try model(channels: 2))).accessibilityLabel
        #expect(label.contains("0 Hz"))
        #expect(label.contains("22.05 kHz"), "the label does not state the file's own Nyquist")
        #expect(label.contains("-120") || label.contains("−120") || label.contains("120"))
        #expect(label.contains("dBFS"))
        #expect(label.contains("2 channels"))
        #expect(label.hasPrefix("Spectrogram."), "the section is not announced by name")
    }

    /// And what it must refuse to claim.
    @Test("the label states what the drawing is, never what it implies")
    func labelClaimsNothing() throws {
        let label = SpectrogramCopy.text(for: .model(try model())).accessibilityLabel
        #expect(label.contains("does not, on its own, establish how the file was produced"))
    }

    @Test("the Nyquist stated follows the file", arguments: [(44_100.0, "22.05 kHz"), (96_000.0, "48 kHz"), (192_000.0, "96 kHz")])
    func nyquistFollowsTheFile(sampleRate: Double, expected: String) throws {
        let label = SpectrogramCopy.text(for: .model(try model(sampleRate: sampleRate))).accessibilityLabel
        #expect(label.contains(expected), "the label says \(label)")
    }
}

// MARK: - Visual honesty

@Suite("Presentation — the spectrogram claims nothing")
struct SpectrogramHonestyTests {
    /// Words that would turn a picture of energy into a verdict about a file. The drawing shows where
    /// energy stops; a cutoff is compatible with lossy encoding, with the master and with deliberate
    /// filtering, and separating those is a different capability's job.
    private static let forbiddenClaims = [
        "fake", "fraudulent", "lossy", "transcoded", "quality", "bad quality", "poor quality", "damaged",
        "healthy", "authentic", "original", "suspicious", "verdict", "detected as mp3", "mp3",
        "upscaled", "counterfeit", "genuine", "bitrate", "encoder", "codec",
    ]

    /// Internal vocabulary that must never reach a reader.
    private static let forbiddenInternals = [
        "framelength", "avaudiofile", "vdsp", "stft", "spectrogramstate", "spectrogramoutcome",
        "spectrogrampresentation", "decoding_", "waveform_", "columncount", "bandcount", "dbfs_",
        "nil", "enum",
    ]

    private func everyString() throws -> [String] {
        let states: [SpectrogramPresentation] = [
            .loading,
            .model(try model()),
            .model(try model(sampleRate: 192_000, channels: 6)),
            .model(try emptyModel()),
            .absent,
            .failed(message: "The spectrogram for this file could not be produced."),
        ]
        return states.flatMap { state -> [String] in
            let text = SpectrogramCopy.text(for: state)
            return [text.headline, text.detail, text.accessibilityLabel].compactMap { $0 }
        } + [SpectrogramCopy.title, "Energy in dBFS. Darker is quieter; lighter is louder."]
    }

    @Test("no presented text claims anything about quality or origin")
    func noClaims() throws {
        for string in try everyString() {
            let lowered = string.lowercased()
            for claim in Self.forbiddenClaims {
                #expect(!lowered.contains(claim), "“\(claim)” appears in: \(string)")
            }
        }
    }

    /// Asserted over the **presented strings**, not over identifiers: a technical value the product
    /// deliberately shows exactly as read is a different thing from an internal name leaking out.
    @Test("no presented text exposes an internal name")
    func noInternals() throws {
        for string in try everyString() {
            let lowered = string.lowercased()
            for internalName in Self.forbiddenInternals {
                #expect(!lowered.contains(internalName), "“\(internalName)” appears in: \(string)")
            }
        }
    }

    @Test("no presented text contains an underscore or a wire key")
    func noWireKeys() throws {
        for string in try everyString() {
            #expect(!string.contains("_"), "an internal key style appears in: \(string)")
        }
    }
}

// MARK: - The composition root's translation

@MainActor
@Suite("App — spectrogram presentation translation")
struct SpectrogramTranslationTests {
    /// Total by construction: every flow state maps to exactly one presentation, and none is invented.
    @Test("every flow state has exactly one presentation")
    func translationIsTotal() throws {
        let spectrogram = try model()
        #expect(RootView.spectrogramPresentation(for: .loading) == .loading)
        #expect(RootView.spectrogramPresentation(for: .available(spectrogram)) == .model(spectrogram))
        #expect(RootView.spectrogramPresentation(for: .unavailable) == .absent)
        #expect(
            RootView.spectrogramPresentation(for: .failed(message: "boom")) == .failed(message: "boom")
        )
    }

    /// The message survives the crossing unchanged — it was already human when it was written.
    @Test("a failure message is carried across verbatim")
    func messageSurvives() {
        let message = "The spectrogram for this file could not be produced."
        guard case let .failed(carried) = RootView.spectrogramPresentation(for: .failed(message: message)) else {
            Issue.record("expected a failure"); return
        }
        #expect(carried == message)
    }
}
