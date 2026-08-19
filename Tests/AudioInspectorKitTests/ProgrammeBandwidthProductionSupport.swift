import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
import FeatureImport

@testable import AudioInspectorApp

// Group 6's subject, stated once so no suite has to restate it: **a file, the production decoder, the
// shared read, and the outcome the composition publishes.**
//
// Group 2's suites measure the same fixtures with `ProgrammeBandwidthReference`, which implements the
// method group 1 decided. Group 3's suites feed `SignificantBandwidthAccumulator` chunks directly.
// Neither is production: one is an oracle and the other skips the decoder and the composition. What
// these helpers run is the path a user's file actually takes, and nothing here ever constructs a
// `SignificantBandwidth` by hand.

/// How far above a known edge a reading may sit, in multiples of the analysis resolution.
///
/// The same contract group 2 established, and for the same reason rather than by copying: a Hann
/// window's skirt stays above a relative threshold `T` out to `d(T) = (1 / (π · 10^(T/20)))^(1/3)`
/// bins, which is 4.72 bins at −50 dB, and the overshoot is one-sided upward because a bin below the
/// edge cannot be lit by content that is not there. It is expressed in resolutions and never in hertz,
/// so it means the same thing at every rate.
let productionOvershootInResolutions = 5.0

/// Runs one written fixture through the production path and returns what the composition publishes.
///
/// The decoder is the real `AVFoundationAudioDecoder`, and the generation is the real
/// `SharedPCMAnalysisGeneration` — the same object the coordinator builds, with programme bandwidth
/// sitting in it as the sixth consumer.
func measureThroughProduction(
    _ spec: AudioFixtureSpec, in directory: URL
) async throws -> SignificantBandwidthOutcome {
    try await measureThroughProduction(writeAudioFixture(spec, in: directory))
}

/// The same, for a file that already exists — a rewrapped or externally encoded one.
func measureThroughProduction(_ url: URL) async -> SignificantBandwidthOutcome {
    await SharedPCMAnalysisGeneration(
        decoder: AVFoundationAudioDecoder(resolveURL: { _ in url })
    ).run(for: productionFileReference).significantBandwidth
}

/// The whole shared outcome, for the suites that must also show the other five were untouched.
func measureEveryAnalysisThroughProduction(
    _ spec: AudioFixtureSpec, in directory: URL
) async throws -> SharedPCMAnalysisOutcome {
    let url = try writeAudioFixture(spec, in: directory)
    return await SharedPCMAnalysisGeneration(
        decoder: AVFoundationAudioDecoder(resolveURL: { _ in url })
    ).run(for: productionFileReference)
}

let productionFileReference = AudioFileReference(
    displayName: "fixture", fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
    source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
)

/// The reading a production outcome carries, or `nil` where the outcome is an absence.
///
/// Deliberately **not** collapsing failure into absence: a `.failed` outcome returns through
/// `Issue.record` rather than as a `nil`, because a suite asserting "no value" must not accept an
/// error as proof of it.
func productionReading(
    _ outcome: SignificantBandwidthOutcome, _ comment: Comment,
    sourceLocation: SourceLocation = #_sourceLocation
) -> SignificantBandwidth.Channel?? {
    switch outcome {
    case let .available(model): model.overall
    case .unavailable: SignificantBandwidth.Channel??.some(nil)
    case let .failed(message):
        { Issue.record("\(comment): the production path failed — \(message)", sourceLocation: sourceLocation); return nil }()
    case .cancelled:
        { Issue.record("\(comment): the production path reported cancellation", sourceLocation: sourceLocation); return nil }()
    }
}

/// A production reading must sit at or above a known edge, and within the leakage reach of it.
func expectProductionEdge(
    _ outcome: SignificantBandwidthOutcome, at edge: Double,
    _ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let published = productionReading(outcome, comment, sourceLocation: sourceLocation)
    let overall = try #require(
        published, "\(comment): the production path published no measurement at all",
        sourceLocation: sourceLocation
    )
    let reading = try #require(
        overall, "\(comment): the production path published a measurement carrying no reading",
        sourceLocation: sourceLocation
    )
    let error = reading.frequency - edge
    #expect(
        error >= -reading.resolution,
        "\(comment): read \(reading.frequency) Hz, below the \(edge) Hz edge by more than one bin",
        sourceLocation: sourceLocation
    )
    #expect(
        error <= productionOvershootInResolutions * reading.resolution,
        """
        \(comment): read \(reading.frequency) Hz for a \(edge) Hz edge — \
        \(error / reading.resolution) resolutions above it, past the \
        \(productionOvershootInResolutions) the Hann skirt explains
        """,
        sourceLocation: sourceLocation
    )
}

// MARK: - Fixture vocabulary, shared with group 2 so the evidence is comparable

/// A comb up to `edge`, at a per-component amplitude that keeps a dense comb well inside full scale.
/// Clipping is broadband, so a fixture that clips measures the clipping and not the comb.
func productionProgramme(to edge: Double, level: Float = 0.01) -> AudioFixtureSignal {
    .tones(highest: edge, spacing: 500, lowest: 500, perComponentAmplitude: level)
}

/// A 19–20 kHz band at a stated level **relative to the programme's per-component amplitude**, which
/// is what a per-bin measurement compares.
func productionHighBand(relativeDB: Double, programmeLevel: Float = 0.01) -> AudioFixtureSignal {
    .tones(
        highest: 20_000, spacing: 500, lowest: 19_000,
        perComponentAmplitude: programmeLevel * Float(pow(10.0, relativeDB / 20))
    )
}

func productionSpec(
    _ name: String, _ signal: AudioFixtureSignal, format: AudioFixtureFormat = .wavFloat,
    rate: Double = 48_000, channels: AVAudioChannelCount = 1, frames: AVAudioFrameCount
) -> AudioFixtureSpec {
    AudioFixtureSpec(
        name: name, format: format, signal: signal, sampleRate: rate, channels: channels, frames: frames
    )
}
