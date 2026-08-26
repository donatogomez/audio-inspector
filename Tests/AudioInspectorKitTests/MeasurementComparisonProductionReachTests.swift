import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
@testable import AudioInspectorApp
@testable import FeatureImport

// **What group 5 owes beyond the ten pairs**: which of the comparator's refusals production can
// actually reach, whether a container changes the answer, whether the flow publishes exactly what the
// domain builds, what the whole thing costs, and that a superseded file cannot leave a measurement
// behind — all of it over real files.
@MainActor
@Suite("Feature — the measurement comparison against the production it runs on")
struct MeasurementComparisonProductionReachTests {

    private func programme(
        _ name: String, _ signal: AudioFixtureSignal, format: AudioFixtureFormat = .wavFloat,
        rate: Double = 48_000, channels: AVAudioChannelCount = 1, seconds: Double = 1
    ) -> AudioFixtureSpec {
        productionSpec(
            name, signal, format: format, rate: rate, channels: channels,
            frames: AVAudioFrameCount(rate * seconds)
        )
    }

    // MARK: - Which incompatibilities production can reach

    /// **`methodsDiffer` is unreachable from production today, and that is a finding rather than a
    /// gap in the tests.**
    ///
    /// The comparator refuses three kinds of incompatibility. This measures the same signal across
    /// every rate the pipeline supports, in mono and in stereo, and reads the identities that actually
    /// ran:
    ///
    /// - **true peak** — one oversampling factor and one filter, fixed in `TruePeakAccumulator`;
    /// - **programme bandwidth** — one identifier, `SignificantBandwidthMethod.v1`, the window geometry
    ///   varying by design and deliberately outside the gate;
    /// - **loudness** — one algorithm, and exactly the two weightings the rule was written around.
    ///
    /// So every pair of files this product can produce compares. The refusals stay pinned in
    /// `MeasurementComparisonTests`, which can construct the measurements production cannot yet make,
    /// and this test is what keeps that division honest: **the day production gains a second factor, a
    /// second identifier or a third weighting, this fails** and someone has to decide whether the new
    /// pair is comparable rather than discovering it in a comparison.
    @Test("every method production can produce is compatible with every other")
    func noIncompatibilityIsReachable() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            var measured: [MeasuredFile] = []
            for rate in [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0] {
                for channels in [AVAudioChannelCount(1), 2] {
                    measured.append(try await MeasurementProduction.measure(
                        programme("reach-\(Int(rate))-\(channels)", signal, rate: rate, channels: channels),
                        in: directory
                    ))
                }
            }

            let truePeakMethods = measured.compactMap { $0.truePeak?.method }
            let bandwidthIdentifiers = Set(measured.compactMap { $0.bandwidth?.method.identifier })
            let loudnessMethods = measured.compactMap { $0.loudness?.method }
            #expect(truePeakMethods.count == measured.count, "a rate produced no true peak at all")
            #expect(loudnessMethods.count == measured.count, "a rate produced no loudness at all")

            #expect(
                Set(truePeakMethods.map { "\($0.oversamplingFactor)/\($0.filter.rawValue)" }).count == 1,
                "production now produces more than one true peak method: \(truePeakMethods)"
            )
            #expect(
                bandwidthIdentifiers == [SignificantBandwidthMethod.v1],
                "production now produces more than one bandwidth identity: \(bandwidthIdentifiers)"
            )
            // Two weightings, and both of them the pair the rule admits — read from what ran.
            let weightings = Set(loudnessMethods.map(\.weighting.rawValue))
            #expect(
                weightings == [
                    LoudnessWeightingIdentifier.publishedAt48kHz.rawValue,
                    LoudnessWeightingIdentifier.derivedFrom48kHz.rawValue,
                ],
                "production's loudness weightings are no longer the demonstrated pair: \(weightings)"
            )
            #expect(Set(loudnessMethods.map(\.algorithm.rawValue)).count == 1)

            // And therefore: no pair of these files is refused on its method.
            for first in measured {
                for second in measured {
                    let comparison = MeasurementComparison(
                        first: first.measurements, second: second.measurements
                    )
                    #expect(
                        !comparison.gaps.contains(.methodsDiffer),
                        """
                        \(first.url.lastPathComponent) against \(second.url.lastPathComponent) was \
                        refused on its method — production reached an incompatibility this test says \
                        it cannot
                        """
                    )
                }
            }
        }
    }

    // MARK: - Containers

    /// **A measurement is made of samples, so the container is not part of it.**
    ///
    /// The individual measurements are already tested against every container in their own suites; the
    /// question here is smaller and belongs to this change: does the *comparison* keep its semantics
    /// when the two sides arrive in different wrappers? Two lossless containers of the same audio
    /// compare with no gap, no method refusal and overlapping bandwidth cells, and the two that store
    /// the same 16-bit samples compare **exactly** equal.
    ///
    /// The lossy case is included for the structural claim only: it compares, on the same terms, with
    /// the same fields populated. **Nothing here reads a difference as evidence of anything** — where
    /// the numbers differ, the comparison says they differ and stops, which is the entire boundary this
    /// change is written against.
    @Test("the comparison keeps its semantics across containers", arguments: [
        AudioFixtureFormat.aiff, .alac, .flac, .aac,
    ])
    func acrossContainers(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("container-wav", signal, format: .wav),
                programme("container-\(format)", signal, format: format),
                in: directory
            )
            let c = pair.comparison
            #expect(c.gaps.isEmpty, "\(format) reported \(c.gaps)")
            #expect(c.signalLevels.channels.differingCounts == nil, "\(format) changed the channel count")

            // Every field was compared: nothing fell through to an absence because of the wrapper.
            guard case .byIndex = c.truePeak.channels, case .byIndex = c.programmeBandwidth.channels else {
                Issue.record("\(format) stopped comparing per channel"); return
            }

            // 16-bit integer either side of the same samples: equality, not a tolerance.
            if format == .aiff || format == .alac {
                guard case .same = c.loudness, case .same = c.truePeak.overall,
                      case .same = c.signalLevels.overall.peakSample
                else {
                    Issue.record("""
                    \(format) stores the same 16-bit samples as WAV and did not measure identically — \
                    loudness \(c.loudness), true peak \(c.truePeak.overall), \
                    peak \(c.signalLevels.overall.peakSample)
                    """)
                    return
                }
                guard case let .indistinguishable(a, b) = c.programmeBandwidth.overall, a == b else {
                    Issue.record("\(format) moved the bandwidth reading: \(c.programmeBandwidth.overall.evidence)")
                    return
                }
            }
        }
    }

    // MARK: - What the flow publishes is what the domain builds

    /// **Transparency, end to end, over two real files.**
    ///
    /// A report is on screen for a file the real coordinator inspected; a second real file is compared
    /// against it through the same coordinator. What `ImportFlowModel` publishes must be *exactly*
    /// `MeasurementComparison(first:second:)` over the two bundles those two inspections settled on —
    /// no rounding, no re-derivation, no field assembled on the way through. The expected value is
    /// built by the domain comparator rather than written out by hand, because what is under test here
    /// is the wiring and a hand-written expectation would be testing the rules a second time.
    ///
    /// It also pins the cost: **one decoder and one read per file**, counted through the real decoder.
    @Test("the flow publishes exactly what the domain builds from the two files, for one read each")
    func theFlowPublishesTheDomainsAnswer() async throws {
        try await withTemporaryDirectory { directory in
            let primaryURL = try writeAudioFixture(
                programme("flow-primary", productionProgramme(to: 12_000)), in: directory
            )
            let comparedURL = try writeAudioFixture(
                programme("flow-compared", productionProgramme(to: 16_000, level: 0.02)), in: directory
            )
            let counts = ProductionReadCounts()
            let captured = CapturedOutcomes()

            let flow = ImportFlowModel(action: coordinatorAction(
                for: primaryURL, counting: counts, into: captured, isPrimary: true
            ))
            await flow.selectAndInspect()
            await flow.compare(using: coordinatorAction(
                for: comparedURL, counting: counts, into: captured, isPrimary: false
            ))

            // One decoder and one read **per file** — two inspections, and not one more.
            #expect(counts.decodersMade == 2, "the two files were given \(counts.decodersMade) decoders")
            #expect(counts.decodeCalls == 2, "the two files' samples were read \(counts.decodeCalls) times")

            let primary = try #require(captured.primary, "the primary file was not inspected")
            let compared = try #require(captured.compared, "the compared file was not inspected")
            let firstBundle = try #require(primary.analyses.settledMeasurements)
            let secondBundle = try #require(compared.analyses.settledMeasurements)

            guard case let .ready(technical, measurements, _) = flow.comparison else {
                Issue.record("the flow published \(flow.comparison)"); return
            }
            #expect(technical == FileComparison(first: primary.report, second: compared.report))
            #expect(
                measurements == MeasurementComparison(first: firstBundle, second: secondBundle),
                "the published comparison is not the one the domain builds from these two bundles"
            )
            // And it is a real answer rather than an empty one, so the equality above means something.
            let published = try #require(measurements)
            #expect(published.gaps.isEmpty, "the end-to-end pair reported \(published.gaps)")
            guard case .different = published.loudness,
                  case .separated = published.programmeBandwidth.overall
            else {
                Issue.record("two deliberately different files compared as equal: \(published)"); return
            }
        }
    }

    // MARK: - Stale, over files

    /// **Task 3.3's property, with the measurements coming from real files.**
    ///
    /// B is superseded by C while B's own inspection is held open, and B then finishes late. The pair
    /// on screen must be entirely C's. The three files are deliberately distinguishable — three
    /// different edges and three different levels — so "entirely C" is observed in the numbers rather
    /// than inferred from fields that merely stayed empty.
    ///
    /// **The handshake is a continuation, not a sleep.** The real coordinator runs to completion and
    /// the *settled outcome* is what waits, which is exactly where `ImportFlowModel` takes the
    /// measurements from. No polling, no `Task.yield()`, and the file is genuinely decoded.
    @Test("a superseded file leaves no measurement behind, over real files")
    func staleOverRealFiles() async throws {
        try await withTemporaryDirectory { directory in
            let a = try writeAudioFixture(programme("stale-a", productionProgramme(to: 10_000)), in: directory)
            let b = try writeAudioFixture(
                programme("stale-b", productionProgramme(to: 14_000, level: 0.02)), in: directory
            )
            let cURL = try writeAudioFixture(
                programme("stale-c", productionProgramme(to: 18_000, level: 0.04)), in: directory
            )

            let captured = CapturedOutcomes()
            let flow = ImportFlowModel(action: coordinatorAction(
                for: a, counting: nil, into: captured, isPrimary: true
            ))
            await flow.selectAndInspect()

            // B is held after its inspection has finished and before its outcome is returned.
            let heldB = HeldInspection(url: b)
            let comparingB = Task { await flow.compare(using: heldB.run) }
            await heldB.waitUntilHeld()

            // C supersedes it and finishes.
            let capturedC = CapturedOutcomes()
            await flow.compare(using: coordinatorAction(
                for: cURL, counting: nil, into: capturedC, isPrimary: false
            ))
            // Only now does B come back, under an operation number that is no longer current.
            heldB.release()
            await comparingB.value

            let primary = try #require(captured.primary)
            let cOutcome = try #require(capturedC.compared)
            let primaryBundle = try #require(primary.analyses.settledMeasurements)
            let comparedBundle = try #require(cOutcome.analyses.settledMeasurements)
            let expected = MeasurementComparison(first: primaryBundle, second: comparedBundle)
            guard case let .ready(technical, measurements, _) = flow.comparison else {
                Issue.record("the flow published \(flow.comparison)"); return
            }
            #expect(technical == FileComparison(first: primary.report, second: cOutcome.report))
            #expect(measurements == expected, "the published pair is not entirely C's")

            // Distinguishable in the numbers, not only in the identity: B's edge and level are between
            // A's and C's, so a mixture would show.
            let published = try #require(measurements)
            let readings = try #require(published.programmeBandwidth.overall.readings)
            let cBundle = try #require(cOutcome.analyses.settledMeasurements)
            let cReading = try #require(cBundle.programmeBandwidth?.overall)
            #expect(
                readings.second == cReading,
                "the bandwidth beside the report is not C's: \(published.programmeBandwidth.overall.evidence)"
            )
        }
    }

    // MARK: - The harness this suite drives the flow with

    /// The outcomes the flow is about to consume, kept so a test can build the domain's own answer
    /// from them.
    @MainActor
    final class CapturedOutcomes {
        var primary: (report: InspectionReport, analyses: InspectionAnalyses)?
        var compared: (report: InspectionReport, analyses: InspectionAnalyses)?
    }

    /// A `SourceInspectionAction` that runs the **real** coordinator over one file and records what it
    /// produced. This is the composition root's own construction, with the decoder wrapped only where a
    /// test is counting.
    private func coordinatorAction(
        for url: URL, counting counts: ProductionReadCounts?, into captured: CapturedOutcomes,
        isPrimary: Bool
    ) -> SourceInspectionAction {
        { onUpdate in
            let coordinator = SourceInspectionCoordinator(makeDecoder: { url in
                let real = AVFoundationAudioDecoder(resolveURL: { _ in url })
                guard let counts else { return real }
                counts.decodersMade += 1
                return CountingDecoder(wrapped: real, counts: counts)
            })
            let outcome = await coordinator.inspect(url, onUpdate: onUpdate)
            if case let .inspected(report, analyses) = outcome {
                if isPrimary { captured.primary = (report, analyses) }
                else { captured.compared = (report, analyses) }
            }
            return outcome
        }
    }

    /// A real inspection whose **settled outcome** is held back until the test releases it.
    ///
    /// The report and every update reach the flow as they normally would; what waits is the return,
    /// which is where the measurements are taken from. That is the only seam a stale test needs, and
    /// it is a continuation rather than a delay.
    @MainActor
    private final class HeldInspection {
        let url: URL
        private var held: CheckedContinuation<Void, Never>?
        private var gate: CheckedContinuation<Void, Never>?
        private var isHeld = false

        init(url: URL) { self.url = url }

        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            let outcome = await SourceInspectionCoordinator().inspect(url, onUpdate: onUpdate)
            isHeld = true
            held?.resume(); held = nil
            await withCheckedContinuation { gate = $0 }
            return outcome
        }

        func waitUntilHeld() async {
            guard !isHeld else { return }
            await withCheckedContinuation { held = $0 }
        }

        func release() { gate?.resume(); gate = nil }
    }
}
