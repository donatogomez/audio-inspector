import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureAnalysis
@testable import FeatureImport

// **Group 5's fixture pairs, carried all the way to the words on screen.**
//
// `MeasurementComparisonPresentationTests` pins the vocabulary against measurements it wrote itself,
// which is right for a rule about words and proves nothing about what a real pair of files produces.
// This suite closes that: two real files, the real decoder, the real shared read, the real domain
// comparator, the real formatter — and then assertions on the **strings**.
//
// Nothing is fabricated anywhere along the way. Where a string is asserted exactly it is because the
// number behind it is evidence: +6 dB of gain is 20·log₁₀(2), which reads `+6.0 LU` at the display
// precision EBU Tech 3341 states.
@MainActor
@Suite("Feature — what the measurement comparison says about real files")
struct MeasurementComparisonSurfaceTests {

    private func programme(
        _ name: String, _ signal: AudioFixtureSignal,
        rate: Double = 48_000, channels: AVAudioChannelCount = 1, seconds: Double = 1
    ) -> AudioFixtureSpec {
        productionSpec(
            name, signal, rate: rate, channels: channels, frames: AVAudioFrameCount(rate * seconds)
        )
    }

    private func blocks(_ pair: MeasuredPair) -> [MeasurementBlockDisplay] {
        MeasurementComparisonFormatter.blocks(for: pair.comparison)
    }

    private func rowNamed(_ name: String, _ pair: MeasuredPair) throws -> MeasurementRowDisplay {
        let rows = blocks(pair).flatMap(\.rows)
        return try #require(rows.first { $0.name == name }, "no row named \(name)")
    }

    private func everyString(_ pair: MeasuredPair) -> [String] {
        blocks(pair).flatMap { block -> [String] in
            [block.title] + [block.channelNote].compactMap { $0 } + block.rows.flatMap { row in
                [row.name, row.outcome.text, row.accessibilityLabel]
                    + [row.first.value, row.first.detail, row.second.value, row.second.detail,
                       row.difference, row.precisionNote].compactMap { $0 }
            }
        }
    }

    // MARK: Pair 2 — the difference a reader can check by hand

    /// Doubling every sample is **exactly** 20·log₁₀(2) LU, and the row says `+6.0 LU`. The spectral
    /// extent does not move, and the surface says so in the instrument's words rather than calling the
    /// two files alike.
    @Test("pair 2 — a 6 dB gain reads as +6.0 LU, and the bandwidth stays where it was")
    func gainPair() async throws {
        try await withTemporaryDirectory { directory in
            let pair = try await MeasurementProduction.pair(
                programme("surface-gain-a", productionProgramme(to: 16_000, level: 0.01)),
                programme("surface-gain-b", productionProgramme(to: 16_000, level: 0.02)),
                in: directory
            )
            let loudness = try rowNamed(LoudnessCopy.title, pair)
            #expect(loudness.outcome == .different)
            #expect(loudness.difference == "+6.0 LU")
            #expect(loudness.accessibilityLabel.hasSuffix("Difference, +6.0 LU."))

            let bandwidth = try rowNamed(ProgrammeBandwidthCopy.title, pair)
            #expect(bandwidth.outcome == .indistinguishable)
            #expect(bandwidth.difference == nil)

            // The levels moved, and no row but loudness carries a difference.
            let peak = try rowNamed(MeasurementComparisonCopy.peakSample, pair)
            #expect(peak.outcome == .different)
            #expect(peak.difference == nil)
            #expect(try rowNamed(TruePeakCopy.title, pair).difference == nil)
        }
    }

    // MARK: Pair 7 — a difference published across two weightings

    /// **The delta appears even though the two files ran different K-weighting constructions**, which
    /// is the whole point of the allow-list: 44.1 kHz runs the rediscretised prototype and 48 kHz the
    /// published tables, and the surface neither refuses the comparison nor mentions either identity.
    @Test("pair 7 — the difference is published across two weightings, and no identity is shown")
    func crossWeightingPair() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("surface-44100", signal, rate: 44_100),
                programme("surface-48000", signal, rate: 48_000),
                in: directory
            )
            let first = try #require(pair.first.loudness)
            let second = try #require(pair.second.loudness)
            #expect(
                first.method.weighting != second.method.weighting,
                "both rates ran one weighting — this pair no longer crosses the equivalence"
            )

            let row = try rowNamed(LoudnessCopy.title, pair)
            #expect(row.outcome != .notComparable(reason: MeasurementComparisonCopy.methodsDiffer))
            let difference = try #require(row.difference, "no difference was published: \(row.outcome)")
            #expect(difference.hasSuffix(" LU"))
            #expect(!difference.contains("LUFS"))

            // Neither weighting's slug reaches the reader.
            for text in everyString(pair) {
                #expect(!text.contains(first.method.weighting.rawValue))
                #expect(!text.contains(second.method.weighting.rawValue))
            }
        }
    }

    // MARK: Pairs 8 and 9 — the two words about the grid

    /// **`Indistinguishable at these resolutions`, never `Same`.** Two rates put one 16 kHz edge in two
    /// bins whose centres differ and whose cells overlap; the surface says the analysis did not separate
    /// them, which is a statement about the instrument.
    @Test("pair 8 — overlapping cells are described by the instrument, not by the files")
    func indistinguishablePair() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("surface-88200", signal, rate: 88_200),
                programme("surface-96000", signal, rate: 96_000),
                in: directory
            )
            let row = try rowNamed(ProgrammeBandwidthCopy.title, pair)
            #expect(row.outcome.text == "Indistinguishable at these resolutions")
            #expect(row.outcome.text != "Same")
            #expect(row.difference == nil)
            // Each side's own resolution is on screen, because the outcome refers to them.
            #expect(row.first.detail?.contains(ProgrammeBandwidthCopy.resolutionTitle) == true)
            #expect(row.second.detail?.contains(ProgrammeBandwidthCopy.resolutionTitle) == true)
            #expect(row.first.detail != nil && row.first.detail?.contains("±") == false)
        }
    }

    /// **`Separated at these resolutions`, never `Different files`** — and this pair is the one that
    /// needed the precision note. Two edges a whole bin apart round to the *same* displayed figure,
    /// because no digit finer than a bin may be shown; without a sentence saying so the row would read
    /// as a contradiction.
    @Test("pair 9 — separated readings that round alike say why, and never that the files differ")
    func separatedPair() async throws {
        try await withTemporaryDirectory { directory in
            let bin = 48_000.0 / 2_048.0
            let pair = try await MeasurementProduction.pair(
                programme("surface-edge-lower", productionProgramme(to: 16_000)),
                programme("surface-edge-upper", productionProgramme(to: 16_000 + bin)),
                in: directory
            )
            let row = try rowNamed(ProgrammeBandwidthCopy.title, pair)
            #expect(row.outcome.text == "Separated at these resolutions")
            #expect(row.difference == nil)

            // The two readings really are one bin apart and really do display alike — which is why the
            // note exists rather than being a hypothetical.
            #expect(row.first.value == row.second.value, "this pair no longer exercises the note")
            #expect(row.precisionNote == MeasurementComparisonCopy.separatedButRoundsAlike)
            #expect(row.accessibilityLabel.contains("different bins"))

            for text in everyString(pair) {
                for phrase in ["different files", "same file", "cutoff", "cut-off", "filtered"] {
                    #expect(!text.lowercased().contains(phrase), "\"\(text)\" says \(phrase)")
                }
            }
        }
    }

    // MARK: Pair 10 — a real absence

    /// A tenth of a second is less than one BS.1770 gating block, so the second file genuinely has no
    /// integrated loudness. The row says which file had none, **shows no number on either side**, and
    /// leaves the other three measurements comparing as they were.
    @Test("pair 10 — a real absence is named, is not a zero, and takes nothing with it")
    func absencePair() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("surface-long", signal), programme("surface-short", signal, seconds: 0.1),
                in: directory
            )
            #expect(pair.second.loudness == nil, "the short file measured a loudness after all")

            let row = try rowNamed(LoudnessCopy.title, pair)
            #expect(row.outcome == .notComparable(reason: MeasurementComparisonCopy.secondHasNoValue))
            #expect(row.difference == nil)

            // **The first file's own figure is on screen, and it is the one production measured.**
            // Taken from the measurement rather than written out, so the assertion cannot drift from
            // the fixture — and so it is genuinely testing that the number survived the comparison
            // rather than that someone typed the same string twice.
            let measured = try #require(pair.first.loudness).integratedLoudness
            #expect(row.first.value == HumanFormat.loudnessFullScale(measured))
            #expect(row.second.value == nil, "the file with no loudness was given one")
            // Never a zero, and never a word that reads as a fault.
            #expect(!row.accessibilityLabel.contains("0.0 LUFS"))
            #expect(!row.accessibilityLabel.contains("0.0 LU"))
            for word in ["failed", "error", "invalid"] {
                #expect(!row.accessibilityLabel.lowercased().contains(word))
            }

            // The siblings still carry their values, because it is the same signal.
            #expect(try rowNamed(MeasurementComparisonCopy.peakSample, pair).outcome == .same)
            #expect(try rowNamed(TruePeakCopy.title, pair).outcome == .same)
            #expect(try rowNamed(ProgrammeBandwidthCopy.title, pair).outcome == .indistinguishable)
        }
    }

    /// **The same pair with the two files swapped**, so nothing about the rule is positional: the file
    /// that measured keeps its figure whichever column it is in, and the outcome names the other one.
    @Test("pair 10 reversed — the surviving figure follows the file, not the column")
    func absencePairReversed() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("surface-short-first", signal, seconds: 0.1),
                programme("surface-long-second", signal),
                in: directory
            )
            #expect(pair.first.loudness == nil, "the short file measured a loudness after all")

            let row = try rowNamed(LoudnessCopy.title, pair)
            #expect(row.outcome == .notComparable(reason: MeasurementComparisonCopy.firstHasNoValue))
            let measured = try #require(pair.second.loudness).integratedLoudness
            #expect(row.first.value == nil, "the file with no loudness was given one")
            #expect(row.second.value == HumanFormat.loudnessFullScale(measured))
            #expect(row.difference == nil)
            #expect(row.accessibilityLabel.contains(MeasurementComparisonCopy.noValue))
            #expect(row.accessibilityLabel.contains(HumanFormat.loudnessFullScale(measured)))
        }
    }

    // MARK: Pair 6 — a channel-count mismatch

    /// The overall figures compare; no index does. **No channel is invented on either side**, and the
    /// note names the two counts without naming a layout.
    @Test("pair 6 — a channel mismatch is stated and no channel is invented")
    func channelMismatchPair() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("surface-mono", signal, channels: 1),
                programme("surface-stereo", signal, channels: 2),
                in: directory
            )
            let withNotes = blocks(pair).filter { $0.channelNote != nil }
            #expect(withNotes.count == 3, "\(withNotes.map(\.title)) carried the mismatch")
            for block in withNotes {
                let note = try #require(block.channelNote)
                #expect(note.contains("1 and 2"))
                for word in ["left", "right", "stereo", "mono"] {
                    #expect(!note.lowercased().contains(word), "\"\(note)\" names a layout")
                }
            }
            // Loudness has no channels, so it says nothing about them.
            let loudness = try #require(blocks(pair).first { $0.title == LoudnessCopy.title })
            #expect(loudness.channelNote == nil)

            // Nothing rendered a per-channel breakdown across the mismatch.
            for row in blocks(pair).flatMap(\.rows) {
                #expect(row.first.detail == nil || row.name == ProgrammeBandwidthCopy.title)
            }
            // And the overall figures did compare.
            #expect(try rowNamed(MeasurementComparisonCopy.peakSample, pair).outcome == .same)
            #expect(try rowNamed(LoudnessCopy.title, pair).difference != nil)
        }
    }

    // MARK: The whole way through the flow

    /// **Two real files, the real flow, the real translation, the real formatter.**
    ///
    /// It drives `ImportFlowModel` with the coordinator on both sides, translates its state exactly as
    /// `RootView` does, and asserts that the sub-section renders the measurements the two inspections
    /// settled on. The expected value is built by the domain comparator over the same two bundles, so
    /// what is under test is the wiring rather than the rules a second time.
    @Test("the surface renders the measurements the two real files settled on")
    func endToEndThroughTheFlow() async throws {
        try await withTemporaryDirectory { directory in
            let primaryURL = try writeAudioFixture(
                programme("flow-surface-a", productionProgramme(to: 12_000)), in: directory
            )
            let comparedURL = try writeAudioFixture(
                programme("flow-surface-b", productionProgramme(to: 16_000, level: 0.02)), in: directory
            )
            let captured = Captured()
            let flow = ImportFlowModel(action: action(for: primaryURL, into: captured, isPrimary: true))
            await flow.selectAndInspect()
            await flow.compare(using: action(for: comparedURL, into: captured, isPrimary: false))

            guard case let .ready(_, measurements) = Self.presentation(for: flow.comparison) else {
                Issue.record("the flow published \(flow.comparison)"); return
            }
            let published = try #require(measurements, "the sub-section was given nothing to render")

            let primary = try #require(captured.primary)
            let compared = try #require(captured.compared)
            let firstBundle = try #require(primary.analyses.settledMeasurements)
            let secondBundle = try #require(compared.analyses.settledMeasurements)
            #expect(published == MeasurementComparison(first: firstBundle, second: secondBundle))

            // And it renders as a real answer rather than an empty one.
            let rows = MeasurementComparisonFormatter.blocks(for: published).flatMap(\.rows)
            #expect(rows.count == 7)
            let bandwidth = try #require(rows.first { $0.name == ProgrammeBandwidthCopy.title })
            #expect(bandwidth.outcome == .separated)
            let loudness = try #require(rows.first { $0.name == LoudnessCopy.title })
            #expect(loudness.difference != nil)
            for row in rows where row.name != LoudnessCopy.title {
                #expect(row.difference == nil, "\(row.name) grew a difference on the way to the surface")
            }
        }
    }

    /// **Until both files have settled, the sub-section says so** rather than rendering an empty table —
    /// the technical rows above it are already complete, and an empty area would read as a defect.
    @Test("a comparison whose measurements have not settled says what is happening")
    func waitingForBothSides() {
        let waiting = MeasurementComparisonSection(comparison: nil)
        #expect(waiting.comparison == nil)
        #expect(!MeasurementComparisonCopy.waiting.isEmpty)
        for word in ["failed", "error", "unavailable"] {
            #expect(!MeasurementComparisonCopy.waiting.lowercased().contains(word))
        }
    }

    // MARK: The harness

    @MainActor
    final class Captured {
        var primary: (report: InspectionReport, analyses: InspectionAnalyses)?
        var compared: (report: InspectionReport, analyses: InspectionAnalyses)?
    }

    /// The same translation `RootView` performs, kept here so the mapping is exercised without a view —
    /// the precedent `ComparisonFlowPresentationTests` set.
    static func presentation(for state: ImportFlowModel.ComparisonState) -> ComparisonPresentation {
        switch state {
        case .none: .none
        case .loading: .loading
        case let .ready(comparison, measurements): .ready(comparison, measurements: measurements)
        case let .failed(message): .failed(message: message)
        }
    }

    private func action(
        for url: URL, into captured: Captured, isPrimary: Bool
    ) -> SourceInspectionAction {
        { onUpdate in
            let outcome = await SourceInspectionCoordinator().inspect(url, onUpdate: onUpdate)
            if case let .inspected(report, analyses) = outcome {
                if isPrimary { captured.primary = (report, analyses) }
                else { captured.compared = (report, analyses) }
            }
            return outcome
        }
    }
}
