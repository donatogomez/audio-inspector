import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp

/// The `measurements.signalLevels` wire contract (group 6 of `add-computed-technical-properties`):
/// additive to `schemaVersion` 1, never inside `technicalProperties`, exported in the domain's own
/// linear amplitude — never dBFS, which is a presentation concern applied only in `FeatureAnalysis`.
/// Inspected exclusively via `Codable` (`JSONValue`), like every other export contract test.
@Suite("Export — signal level measurements JSON contract")
struct JSONReportExportMeasurementsTests {

    // MARK: - Fixtures

    private func channel(
        sampleCount: Int = 44_100,
        peak: Float? = 0.5,
        rms: Float? = 0.25,
        dcOffset: Float? = 0.001,
        clipped: Int = 0
    ) -> SignalLevelMetrics.Channel {
        SignalLevelMetrics.Channel(
            sampleCount: sampleCount, peakSample: peak, rms: rms, dcOffset: dcOffset, clippedSampleCount: clipped
        )
    }

    private func metrics(
        channels: [SignalLevelMetrics.Channel],
        overallPeak: Float?,
        overallRMS: Float?,
        overallDCOffset: Float?,
        overallClipped: Int
    ) -> SignalLevelMetrics {
        SignalLevelMetrics(
            channels: channels,
            overallPeakSample: overallPeak,
            overallRMS: overallRMS,
            overallDCOffset: overallDCOffset,
            overallClippedSampleCount: overallClipped
        )
    }

    private var monoMetrics: SignalLevelMetrics {
        metrics(channels: [channel()], overallPeak: 0.5, overallRMS: 0.25, overallDCOffset: 0.001, overallClipped: 0)
    }

    private var stereoMetrics: SignalLevelMetrics {
        metrics(
            channels: [channel(peak: 0.708, rms: 0.3, dcOffset: 0.002, clipped: 3), channel(peak: 0.5, rms: 0.2, dcOffset: -0.001, clipped: 0)],
            overallPeak: 0.708, overallRMS: 0.25, overallDCOffset: 0.0005, overallClipped: 3
        )
    }

    // MARK: 1-2. Overall + per-channel mono

    @Test func overallAndMonoChannelExportTheLinearDomainValues() throws {
        let object = try exportValue(report(status: .completed), signalLevelMetrics: monoMetrics)
        let signalLevels = try #require(object["measurements"]?["signalLevels"])

        let overall = try #require(signalLevels["overall"])
        #expect(overall["peakSample"]?.double == 0.5)
        #expect(overall["rms"]?.double == 0.25)
        #expect(overall["dcOffset"]?.double?.isApproximately(0.001) == true)
        #expect(overall["clippedSampleCount"]?.int == 0)

        let channels = try #require(signalLevels["channels"]?.array)
        #expect(channels.count == 1)
        #expect(channels[0]["sampleCount"]?.int == 44_100)
        #expect(channels[0]["peakSample"]?.double == 0.5)
    }

    // MARK: 3. Per-channel stereo

    @Test func stereoExportsOneEntryPerChannelInOrder() throws {
        let object = try exportValue(report(status: .completed), signalLevelMetrics: stereoMetrics)
        let channels = try #require(object["measurements"]?["signalLevels"]?["channels"]?.array)

        #expect(channels.count == 2)
        #expect(channels[0]["peakSample"]?.double.map { abs($0 - 0.708) < 0.0001 } == true)
        #expect(channels[0]["clippedSampleCount"]?.int == 3)
        #expect(channels[1]["peakSample"]?.double == 0.5)
        #expect(channels[1]["clippedSampleCount"]?.int == 0)
    }

    // MARK: 4. Multichannel

    @Test func multichannelExportsEveryChannelExactlyOnce() throws {
        let six = metrics(
            channels: (1 ... 6).map { channel(peak: Float($0) / 10) },
            overallPeak: 0.6, overallRMS: 0.25, overallDCOffset: 0.001, overallClipped: 0
        )
        let object = try exportValue(report(status: .completed), signalLevelMetrics: six)
        let channels = try #require(object["measurements"]?["signalLevels"]?["channels"]?.array)
        #expect(channels.count == 6)
        for (index, channel) in channels.enumerated() {
            #expect(channel["peakSample"]?.double.map { abs($0 - Double(index + 1) / 10) < 0.0001 } == true)
        }
    }

    // MARK: 5. Zero frames — null, never a fabricated zero

    @Test func zeroFramesExportsExplicitNullNeverAFabricatedZero() throws {
        let empty = channel(sampleCount: 0, peak: nil, rms: nil, dcOffset: nil, clipped: 0)
        let zeroFrame = metrics(channels: [empty], overallPeak: nil, overallRMS: nil, overallDCOffset: nil, overallClipped: 0)

        let object = try exportValue(report(status: .completed), signalLevelMetrics: zeroFrame)
        let signalLevels = try #require(object["measurements"]?["signalLevels"])

        let overall = try #require(signalLevels["overall"])
        #expect(overall["peakSample"]?.isNull == true)
        #expect(overall["rms"]?.isNull == true)
        #expect(overall["dcOffset"]?.isNull == true)
        #expect(overall["clippedSampleCount"]?.int == 0) // always defined, never null

        let channelObject = try #require(signalLevels["channels"]?.array?.first)
        #expect(channelObject["sampleCount"]?.int == 0)
        #expect(channelObject["peakSample"]?.isNull == true)
        #expect(channelObject["clippedSampleCount"]?.int == 0)
    }

    /// The key must be **present with `null`**, not omitted — distinguishing "not computable" from a
    /// value this schema version simply doesn't define, the same convention `PropertyDTO` already uses.
    @Test func notComputableKeysArePresentWithExplicitNullNotOmitted() throws {
        let empty = channel(sampleCount: 0, peak: nil, rms: nil, dcOffset: nil, clipped: 0)
        let zeroFrame = metrics(channels: [empty], overallPeak: nil, overallRMS: nil, overallDCOffset: nil, overallClipped: 0)
        let object = try exportValue(report(status: .completed), signalLevelMetrics: zeroFrame)
        let overall = try #require(object["measurements"]?["signalLevels"]?["overall"])
        #expect(overall.keys?.isSuperset(of: ["peakSample", "rms", "dcOffset", "clippedSampleCount"]) == true)
    }

    // MARK: 6. Peak > 1 preserved

    @Test func aPeakBeyondFullScaleExportsExactlyAsMeasuredNeverClamped() throws {
        let outOfRange = metrics(channels: [channel(peak: 1.5)], overallPeak: 1.5, overallRMS: 0.3, overallDCOffset: 0, overallClipped: 0)
        let object = try exportValue(report(status: .completed), signalLevelMetrics: outOfRange)
        let overall = try #require(object["measurements"]?["signalLevels"]?["overall"])
        #expect(overall["peakSample"]?.double == 1.5)
    }

    // MARK: 7. RMS 0 — real computed silence, not absence

    @Test func realSilenceExportsAGenuineZeroNeverNull() throws {
        let silent = metrics(channels: [channel(peak: 0, rms: 0, dcOffset: 0, clipped: 0)], overallPeak: 0, overallRMS: 0, overallDCOffset: 0, overallClipped: 0)
        let object = try exportValue(report(status: .completed), signalLevelMetrics: silent)
        let overall = try #require(object["measurements"]?["signalLevels"]?["overall"])
        #expect(overall["rms"]?.double == 0)
        #expect(overall["rms"]?.isNull == false)
    }

    // MARK: 8-9. DC offset sign

    @Test func dcOffsetExportsPositiveAndNegativeExactly() throws {
        let positive = metrics(channels: [channel(dcOffset: 0.0023)], overallPeak: 0.5, overallRMS: 0.2, overallDCOffset: 0.0023, overallClipped: 0)
        let negative = metrics(channels: [channel(dcOffset: -0.0041)], overallPeak: 0.5, overallRMS: 0.2, overallDCOffset: -0.0041, overallClipped: 0)

        let positiveObject = try exportValue(report(status: .completed), signalLevelMetrics: positive)
        let negativeObject = try exportValue(report(status: .completed), signalLevelMetrics: negative)

        #expect(positiveObject["measurements"]?["signalLevels"]?["overall"]?["dcOffset"]?.double?.isApproximately(0.0023) == true)
        #expect(negativeObject["measurements"]?["signalLevels"]?["overall"]?["dcOffset"]?.double?.isApproximately(-0.0041) == true)
    }

    // MARK: 10-11. Clipped sample count

    @Test func clippedCountExportsZeroAndPositiveAsPlainIntegers() throws {
        let none = metrics(channels: [channel(clipped: 0)], overallPeak: 0.5, overallRMS: 0.2, overallDCOffset: 0, overallClipped: 0)
        let many = metrics(channels: [channel(clipped: 12_431)], overallPeak: 0.5, overallRMS: 0.2, overallDCOffset: 0, overallClipped: 12_431)

        let noneObject = try exportValue(report(status: .completed), signalLevelMetrics: none)
        let manyObject = try exportValue(report(status: .completed), signalLevelMetrics: many)

        #expect(noneObject["measurements"]?["signalLevels"]?["overall"]?["clippedSampleCount"]?.int == 0)
        #expect(manyObject["measurements"]?["signalLevels"]?["overall"]?["clippedSampleCount"]?.int == 12_431)
    }

    // MARK: 12. No absolute paths, no filesystem metadata

    @Test func noPathOrFilesystemMetadataLeaksThroughMeasurements() throws {
        let object = try exportValue(report(status: .completed), signalLevelMetrics: stereoMetrics)
        let keys = allKeys(object)
        for forbidden in ["path", "url", "bookmark", "directory", "filename"] {
            #expect(!keys.contains { $0.lowercased().contains(forbidden) }, "“\(forbidden)” is a key in the export")
        }
    }

    // MARK: 13. Exact keys

    @Test func measurementsUsesExactlyTheDocumentedKeys() throws {
        let object = try exportValue(report(status: .completed), signalLevelMetrics: stereoMetrics)
        #expect(object.keys?.contains("measurements") == true)
        #expect(object["measurements"]?.keys == ["signalLevels"])
        #expect(object["measurements"]?["signalLevels"]?.keys == ["overall", "channels"])
        #expect(object["measurements"]?["signalLevels"]?["overall"]?.keys == ["peakSample", "rms", "dcOffset", "clippedSampleCount"])
        let firstChannel = try #require(object["measurements"]?["signalLevels"]?["channels"]?.array?.first)
        #expect(firstChannel.keys == ["sampleCount", "peakSample", "rms", "dcOffset", "clippedSampleCount"])
    }

    // MARK: 14. Determinism

    @Test func theSameMetricsExportByteIdenticalDataTwice() throws {
        let once = try exportData(report(status: .completed), signalLevelMetrics: stereoMetrics)
        let twice = try exportData(report(status: .completed), signalLevelMetrics: stereoMetrics)
        #expect(once == twice)
    }

    // MARK: 15. Report metadata untouched by measurements

    @Test func measurementsDoNotChangeAnyExistingField() throws {
        let withoutMetrics = try exportValue(report(status: .completed))
        let withMetrics = try exportValue(report(status: .completed), signalLevelMetrics: stereoMetrics)

        for key in ["schemaVersion", "generatedAt", "generator", "inspectedFile", "technicalProperties", "warnings", "inspectionStatus"] {
            #expect(withoutMetrics[key] == withMetrics[key], "\(key) changed when measurements were added")
        }
    }

    // MARK: 16. TechnicalProperties never carries a DSP key

    @Test func technicalPropertiesNeverContainsADSPKey() throws {
        let object = try exportValue(report(status: .completed), signalLevelMetrics: stereoMetrics)
        let technicalKeys = try #require(object["technicalProperties"]?.keys)
        for dspKey in ["peakSample", "rms", "dcOffset", "clippedSampleCount", "signalLevels", "measurements"] {
            #expect(!technicalKeys.contains(dspKey), "\(dspKey) leaked into technicalProperties")
        }
    }

    // MARK: 17. Export without metrics stays valid and byte-identical to before this capability

    @Test func exportWithoutMetricsOmitsTheKeyEntirelyAndStaysValid() throws {
        let object = try exportValue(report(status: .completed))
        #expect(object.keys?.contains("measurements") == false)
        #expect(object["schemaVersion"]?.int == 1) // still a valid, decodable v1 document
    }

    @Test func exportIsByteIdenticalWithAndWithoutMetricsWhenMetricsAreNil() throws {
        let explicit = try exportData(report(status: .completed), signalLevelMetrics: nil)
        let implicit = try exportData(report(status: .completed))
        #expect(explicit == implicit)
    }

    // MARK: 18. schemaVersion unchanged

    @Test func schemaVersionStaysOneWithMeasurementsPresent() throws {
        let object = try exportValue(report(status: .completed), signalLevelMetrics: stereoMetrics)
        #expect(object["schemaVersion"]?.int == 1)
    }

    // MARK: 19. A non-finite value fails encoding rather than emitting a fiction

    /// The domain's own public initializer does not itself forbid a non-finite value (that guarantee
    /// lives upstream, at `PCMChunk`'s construction boundary) — so this constructs one directly to
    /// audit the export layer's own behaviour if that upstream guarantee were ever bypassed: it must
    /// fail loudly, never emit `"NaN"`/`"Infinity"` as if they were real JSON numbers.
    @Test func aNonFiniteValueFailsEncodingRatherThanProducingAFiction() {
        let corrupted = metrics(
            channels: [channel(peak: .infinity)], overallPeak: .infinity, overallRMS: 0.2, overallDCOffset: 0, overallClipped: 0
        )
        #expect(throws: (any Error).self) {
            try exportData(report(status: .completed), signalLevelMetrics: corrupted)
        }
    }

}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}
