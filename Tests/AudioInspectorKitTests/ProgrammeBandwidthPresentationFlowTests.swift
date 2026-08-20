import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import FeatureImport

@testable import AudioInspectorApp
@testable import FeatureAnalysis

// **A real file all the way to the words on screen.** File, real decoder, shared PCM read, the
// composition's outcome, the flow's state, the composition root's mapping, and the strings the report
// surface would draw. Nothing is constructed by hand at any point in the chain, which is the property
// this suite exists for: a value that reached the model and stopped there would be a wiring bug nobody
// could see, and one that reached the surface as the wrong words would be worse.
//
// It runs at the level the repository already tests presentation at — `LoudnessProductionVectorTests`'
// own shape. There are no view snapshots here because there are none anywhere in this project, and
// group 7 is not the place to introduce a visual-testing framework.
@Suite("App — programme bandwidth reaches the report surface")
struct ProgrammeBandwidthPresentationFlowTests {

    /// The whole chain, in one call, with no step skipped or simulated.
    private func surface(
        _ spec: AudioFixtureSpec, in directory: URL
    ) async throws -> SignificantBandwidthPresentation {
        let outcome = try await measureThroughProduction(spec, in: directory)
        let state = try #require(
            SignificantBandwidthState(outcome),
            "the flow discarded \(outcome) — only a cancelled outcome may do that"
        )
        return RootView.programmeBandwidthPresentation(for: state)
    }

    private func rowValue(_ presentation: SignificantBandwidthPresentation) -> String? {
        guard case let .measurement(model) = presentation else { return nil }
        return ProgrammeBandwidthCopy.row(for: model)?.value
    }

    // MARK: A and B — a measured programme becomes a row

    /// The strings a known edge may legitimately display, **derived from the contract rather than from
    /// a run**: the reading sits at or above the edge and within 5 resolutions of it (group 6's
    /// one-sided leakage bound), and the surface rounds to the smallest power of ten at least as coarse
    /// as the resolution — 100 Hz at every supported rate. A 20 kHz edge therefore reads somewhere in
    /// [20 000, 20 117] Hz, which rounds to 20 000 or 20 100 and displays as "20 kHz" or "20.1 kHz".
    /// Anything else — a finer digit, a different kilohertz, an absence — fails.
    private func permittedDisplays(forEdge edge: Double, resolution: Double = 23.4375) -> Set<String> {
        let top = edge + 5 * resolution
        let step = 100.0
        let lowest = (edge / step).rounded()
        let highest = (top / step).rounded()
        return Set(stride(from: lowest, through: highest, by: 1).map {
            HumanFormat.programmeBandwidth($0 * step, resolution: resolution)
        })
    }

    /// **Surface fidelity**: whatever was measured, the row shows exactly what the rounding rule makes
    /// of it. Asserted separately from the value's correctness, which is group 6's question — this one
    /// is only whether the last step distorts it.
    private func expectFaithfulRendering(
        _ presentation: SignificantBandwidthPresentation, edge: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        guard case let .measurement(model) = presentation else {
            Issue.record("a \(edge) Hz programme reached the surface as \(presentation)", sourceLocation: sourceLocation)
            return
        }
        let overall = try #require(model.overall, "the measurement carried no reading", sourceLocation: sourceLocation)
        let row = try #require(ProgrammeBandwidthCopy.row(for: model), sourceLocation: sourceLocation)
        #expect(
            row.value == HumanFormat.programmeBandwidth(overall.frequency, resolution: overall.resolution),
            "the row shows \(row.value) for a measured \(overall.frequency) Hz",
            sourceLocation: sourceLocation
        )
        let permitted = permittedDisplays(forEdge: edge, resolution: overall.resolution)
        #expect(
            permitted.contains(row.value),
            "a \(edge) Hz edge displayed \(row.value); the contract permits \(permitted.sorted())",
            sourceLocation: sourceLocation
        )
    }

    @Test("a 16 kHz programme reaches the surface as a row, at the resolution it was measured on")
    func programmeAt16kHz() async throws {
        try await withTemporaryDirectory { directory in
            let presentation = try await surface(
                productionSpec("surface-16k", productionProgramme(to: 16_000), frames: 48_000), in: directory
            )
            try expectFaithfulRendering(presentation, edge: 16_000)
            guard case let .measurement(model) = presentation else { return }
            let row = try #require(ProgrammeBandwidthCopy.row(for: model))
            let resolution = try #require(ProgrammeBandwidthCopy.resolutionRow(for: model))
            #expect(row.name == "Programme bandwidth")
            #expect(resolution.name == "Analysis resolution")
            #expect(resolution.value == "23 Hz", "the 48 kHz grid displayed \(resolution.value)")
            #expect(ProgrammeBandwidthCopy.text(for: presentation) == nil, "a measured row gained a statement")
        }
    }

    @Test("a 20 kHz programme reaches the surface as its own row")
    func programmeAt20kHz() async throws {
        try await withTemporaryDirectory { directory in
            let presentation = try await surface(
                productionSpec("surface-20k", productionProgramme(to: 20_000), frames: 48_000), in: directory
            )
            try expectFaithfulRendering(presentation, edge: 20_000)
        }
    }

    /// The two files produce **different** rows, which is what makes the row a measurement rather than
    /// a constant that happens to render.
    @Test("two different programmes do not display the same value")
    func differentProgrammesDisplayDifferently() async throws {
        try await withTemporaryDirectory { directory in
            let low = try await surface(
                productionSpec("surface-diff-16k", productionProgramme(to: 16_000), frames: 48_000), in: directory
            )
            let high = try await surface(
                productionSpec("surface-diff-20k", productionProgramme(to: 20_000), frames: 48_000), in: directory
            )
            #expect(rowValue(low) != rowValue(high), "two different edges displayed identically")
        }
    }

    // MARK: C — silence is words, never a number

    /// Task 7.3 through the real path: an absence arrives as the report's own not-computable phrasing,
    /// and nothing anywhere turns it into a zero or into the top of the band.
    @Test("digital silence reaches the surface as the not-computable sentence, not as a number")
    func silenceIsAnAbsenceOnTheSurface() async throws {
        try await withTemporaryDirectory { directory in
            let presentation = try await surface(
                productionSpec("surface-silence", .silence, frames: 144_000), in: directory
            )
            #expect(presentation == .absent, "silence reached the surface as \(presentation)")
            let text = try #require(ProgrammeBandwidthCopy.text(for: presentation))
            #expect(text.headline == "Not computable for this file.")
            let everything = [text.headline, text.detail, text.accessibilityLabel].compactMap { $0 }.joined(separator: " ")
            for forbidden in ["0 Hz", "0 kHz", "24 kHz", "Nyquist", "silence", "silent"] {
                #expect(
                    !everything.lowercased().contains(forbidden.lowercased()),
                    "an absent programme bandwidth said \"\(forbidden)\""
                )
            }
        }
    }

    // MARK: D — the impulse control, visible

    /// **The property the whole design exists for, carried to the surface.** An isolated full-scale
    /// click inside a 16 kHz programme must leave the *displayed* row identical to the undisturbed
    /// programme's — not merely the underlying frequency, because a formatter that rounded differently
    /// either side of a transient would put the design's central claim back in doubt at the last step.
    @Test("an isolated click inside a programme does not change the displayed row")
    func anIsolatedClickDoesNotChangeWhatIsShown() async throws {
        try await withTemporaryDirectory { directory in
            let clean = try await surface(
                productionSpec("surface-clean", productionProgramme(to: 16_000), frames: 144_000), in: directory
            )
            let clicked = try await surface(
                productionSpec("surface-clicked",
                               .sum([productionProgramme(to: 16_000), .impulse(amplitude: 0.9, frameIndex: 72_000)]),
                               frames: 144_000),
                in: directory
            )
            let cleanValue = try #require(rowValue(clean))
            let clickedValue = try #require(rowValue(clicked))
            #expect(clickedValue == cleanValue, "a click changed the displayed row from \(cleanValue) to \(clickedValue)")
            #expect(clicked == clean, "a click changed the presentation")
        }
    }

    // MARK: The mapping is total, and the siblings are untouched

    /// Every flow state has exactly one presentation, and none is invented. A `default` that swallowed a
    /// new state into `.loading` is the omission this asserts against.
    @Test func theMappingIsTotalAndInventsNothing() throws {
        let method = try #require(SignificantBandwidthMethod(windowFrames: 2_048, hopFrames: 512, sampleRate: 48_000))
        let channel = try #require(SignificantBandwidth.Channel(frequency: 16_101.5625, resolution: 23.4375))
        let model = try #require(SignificantBandwidth(channels: [channel], method: method))

        #expect(RootView.programmeBandwidthPresentation(for: .loading) == .loading)
        #expect(RootView.programmeBandwidthPresentation(for: .available(model)) == .measurement(model))
        #expect(RootView.programmeBandwidthPresentation(for: .unavailable) == .absent)
        #expect(RootView.programmeBandwidthPresentation(for: .failed(message: "no")) == .failed(message: "no"))
        // A cancelled outcome never becomes a state at all, so it can never reach a surface.
        #expect(SignificantBandwidthState(.cancelled) == nil)
    }

    /// Adding a sixth section changed none of the five before it: the same file produces the same
    /// presentations for its siblings, asserted through the same mapping the report uses.
    @Test("the five siblings are unchanged by the sixth reaching the surface")
    func siblingsAreUnchanged() async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureEveryAnalysisThroughProduction(
                productionSpec("surface-siblings", productionProgramme(to: 16_000), channels: 2, frames: 48_000),
                in: directory
            )
            // Each sibling settled on its own and reached its own presentation, with the sixth present.
            guard case .available = outcome.waveform, case .available = outcome.spectrogram,
                  case .available = outcome.signalLevelMetrics, case .available = outcome.truePeak,
                  case .available = outcome.loudness, case .available = outcome.significantBandwidth
            else {
                Issue.record("an analysis produced nothing: \(outcome)"); return
            }
            #expect(RootView.waveformPresentation(for: try #require(WaveformState(outcome.waveform))) != .loading)
            #expect(RootView.spectrogramPresentation(for: try #require(SpectrogramState(outcome.spectrogram))) != .loading)
            #expect(RootView.truePeakPresentation(for: try #require(TruePeakState(outcome.truePeak))) != .loading)
            #expect(RootView.loudnessPresentation(for: try #require(LoudnessState(outcome.loudness))) != .loading)
            #expect(
                RootView.programmeBandwidthPresentation(for: try #require(SignificantBandwidthState(outcome.significantBandwidth))) != .loading
            )
        }
    }
}
