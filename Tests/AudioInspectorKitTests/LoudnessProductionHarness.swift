import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
@testable import AudioInspectorApp
@testable import FeatureAnalysis
import FeatureImport

// Driving a `LoudnessTestVector` through the **whole production path**, not through the accumulator.
//
// ## Why this exists beside `LoudnessAccumulatorHarness`
//
// That harness hands `PCMChunk`s straight to `LoudnessAccumulator`. The accumulator is production code
// and the targets it meets are the published ones, so those tests are real evidence — but they are
// evidence about **one type**. Between that type and the number a user sees there is a file on disk,
// `AVFoundationAudioDecoder`, a chunk size nobody chose for loudness, four other consumers folding the
// same chunks, and a composition that decides what an absence means. None of that is exercised by
// feeding an array in.
//
// So this harness writes the vector as a **real file** and runs the composition the app runs:
//
//     file → AVFoundationAudioDecoder → SharedPCMAnalysisGeneration → LoudnessOutcome
//
// It is the same construction `SourceInspectionCoordinator` performs, down to the `resolveURL` seam —
// the only thing production supplies that a test cannot, because the reference deliberately carries no
// location (ADR-0010).
//
// **Nothing here builds a `LoudnessMeasurement`.** Every value a test in group 6 asserts on came out of
// the composition, which is the entire point of measuring against production rather than about it.

enum LoudnessProductionHarness {

    /// What one production run of a vector yielded: every analysis's outcome, and the file it read.
    ///
    /// The four other outcomes travel with it because several tasks in this group need them — an
    /// undefined loudness must not disturb the analyses beside it, and a sample beyond full scale must
    /// reach true peak and the signal levels with their own semantics intact.
    struct Run {
        let outcome: SharedPCMAnalysisOutcome
        let url: URL

        var loudness: LoudnessOutcome { outcome.loudness }

        /// The measurement, or `nil` when the standard defines none. `nil` is a real answer here and is
        /// never a failure — a caller that wants the distinction reads `loudness` itself.
        var measurement: LoudnessMeasurement? {
            guard case let .available(measurement) = outcome.loudness else { return nil }
            return measurement
        }

        var integratedLoudness: Double? { measurement?.integratedLoudness }
    }

    /// Writes `vector` as 32-bit float PCM and measures it through the production composition.
    ///
    /// Float, always, for the reason `LoudnessTestVector.fixtureSpec` already states: the published
    /// levels reach −72 dBFS, and 16-bit quantisation would turn the quiet passages into something the
    /// published expectation no longer describes.
    static func run(_ vector: LoudnessTestVector, in directory: URL) async throws -> Run {
        let url = try writeFloatPCMFixture(vector.fixtureSpec, in: directory)
        try confirmFixtureMatchesItsSpecification(vector, at: url)
        return try await run(fileAt: url)
    }

    /// The same run for a file a caller wrote itself — a container other than float WAV, or a signal
    /// the vector catalogue has no reason to carry.
    static func run(fileAt url: URL) async throws -> Run {
        let outcome = await SharedPCMAnalysisGeneration(
            decoder: AVFoundationAudioDecoder(resolveURL: { _ in url })
        ).run(for: reference(for: url))
        return Run(outcome: outcome, url: url)
    }

    /// A vector written at another sample rate, so the multi-rate matrix drives real files rather than
    /// resynthesised arrays.
    static func run(
        _ vector: LoudnessTestVector, at rate: Double, in directory: URL
    ) async throws -> Run {
        try await run(LoudnessAccumulatorHarness.resynthesised(vector, at: rate), in: directory)
    }

    /// Reads the written file back and checks it is the signal the vector describes.
    ///
    /// Without this, a fixture-writing bug would look exactly like a measurement error: the test would
    /// fail against a published target and point at the accumulator. Metadata only — no samples are
    /// reduced here, because a reference implementation on this side is the one thing these suites must
    /// not contain.
    private static func confirmFixtureMatchesItsSpecification(
        _ vector: LoudnessTestVector, at url: URL
    ) throws {
        let metadata = try readBackMetadata(of: url)
        #expect(metadata.sampleRate == vector.sampleRate, "\(vector.name) rate")
        #expect(metadata.channels == vector.channels, "\(vector.name) channels")
        #expect(metadata.frames == AVAudioFramePosition(vector.totalFrames), "\(vector.name) frames")
    }

    /// The extraction `ReportView.exportableLoudness` performs, reproduced because that computed property
    /// is private to the view and SwiftUI's own button is not reachable headlessly. Every non-measurement
    /// state collapses to `nil`, exactly as it does there.
    static func exportableLoudness(_ presentation: LoudnessPresentation) -> LoudnessMeasurement? {
        guard case let .measurement(measurement) = presentation else { return nil }
        return measurement
    }

    /// The safe reference the composition takes. It carries no location by design; the URL reaches the
    /// adapter through `resolveURL`, exactly as it does in the app.
    private static func reference(for url: URL) -> AudioFileReference {
        let name = url.lastPathComponent
        return AudioFileReference(
            displayName: name,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension,
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
        )
    }
}
