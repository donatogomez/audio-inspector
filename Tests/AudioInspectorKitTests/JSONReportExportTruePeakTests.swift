import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp

/// The wire contract for `measurements.truePeak` — a sibling of `measurements.signalLevels` under the
/// same additive rule, added without a `schemaVersion` bump.
///
/// Everything is asserted through `Codable`/`JSONDecoder` over the real exporter, never through
/// `JSONSerialization` and never against a hand-written string, so these tests describe the document a
/// consumer actually receives.
@Suite("Export — measurements.truePeak (schemaVersion 1, additive)")
struct JSONReportExportTruePeakTests {

    // MARK: - Fixtures

    private func method(factor: Int = 8, filter: TruePeakFilterIdentifier = .polyphaseFIRv1) throws -> TruePeakMethod {
        try #require(TruePeakMethod(oversamplingFactor: factor, filter: filter))
    }

    private func measurement(_ peaks: [Float?], sampleCount: Int = 44_100) throws -> TruePeakMeasurement {
        let channels = try peaks.map { peak in
            try #require(TruePeakMeasurement.Channel(
                sampleCount: peak == nil ? 0 : sampleCount, truePeak: peak
            ))
        }
        let built = try method()
        return try #require(TruePeakMeasurement(channels: channels, method: built))
    }

    private func signalLevels() -> SignalLevelMetrics {
        SignalLevelMetrics(
            channels: [SignalLevelMetrics.Channel(
                sampleCount: 44_100, peakSample: 0.5, rms: 0.25, dcOffset: 0.001, clippedSampleCount: 0
            )],
            overallPeakSample: 0.5, overallRMS: 0.25, overallDCOffset: 0.001, overallClippedSampleCount: 0
        )
    }

    // MARK: 1-2. The object, and its overall value

    @Test func truePeakIsASiblingOfSignalLevelsCarryingTheLinearOverallValue() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([0.5]))
        let truePeak = try #require(object["measurements"]?["truePeak"])

        #expect(truePeak["overall"]?.double == 0.5)
        // Its own object under `measurements`, never nested inside `signalLevels` and never hoisted to
        // the envelope.
        #expect(object["truePeak"] == nil)
        #expect(object["measurements"]?["signalLevels"]?["truePeak"] == nil)
    }

    // MARK: 3. Channels

    @Test func eachChannelExportsItsFrameCountAndItsLinearValueInStreamOrder() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([0.8, 0.25]))
        let channels = try #require(object["measurements"]?["truePeak"]?["channels"]?.array)

        #expect(channels.count == 2)
        #expect(channels[0]["sampleCount"]?.int == 44_100)
        // `0.8` has no exact binary form, so it survives `Float` → `Double` as 0.80000001…; the
        // comparison is written the way the signal-levels suite already writes it. `0.25` is exact, so
        // channel order is asserted against an exact value.
        #expect(channels[0]["truePeak"]?.double.map { abs($0 - 0.8) < 0.0001 } == true)
        #expect(channels[1]["truePeak"]?.double == 0.25, "channel order was not preserved")
        // No presentation vocabulary reaches the wire: no channel names, no units, no dBTP.
        for channel in channels {
            #expect(channel["name"] == nil)
            #expect(channel["unit"] == nil)
        }
    }

    @Test func aMonoFileExportsExactlyOneChannel() throws {
        let channels = try #require(
            try exportValue(report(status: .completed), truePeak: try measurement([0.5]))["measurements"]?["truePeak"]?["channels"]?.array
        )
        #expect(channels.count == 1)
    }

    @Test func sixChannelsAreEachExportedExactlyOnceInOrder() throws {
        let peaks: [Float?] = (1 ... 6).map { Float($0) / 10 }
        let object = try exportValue(report(status: .completed), truePeak: try measurement(peaks))
        let channels = try #require(object["measurements"]?["truePeak"]?["channels"]?.array)

        #expect(channels.count == 6)
        for (index, channel) in channels.enumerated() {
            #expect(channel["truePeak"]?.double.map { abs($0 - Double(index + 1) / 10) < 0.0001 } == true)
        }
        #expect(object["measurements"]?["truePeak"]?["overall"]?.double.map { abs($0 - 0.6) < 0.0001 } == true)
    }

    // MARK: 4. A value beyond full scale is exported as measured

    /// The case the whole measurement exists for. A reconstruction above full scale is **not clamped**
    /// on the wire any more than it is on screen — clamping would delete the answer.
    @Test func aValueBeyondFullScaleExportsExactlyAsMeasured() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([1.2, 1.05]))
        let truePeak = try #require(object["measurements"]?["truePeak"])

        #expect(truePeak["overall"]?.double.map { abs($0 - 1.2) < 0.0001 } == true)
        #expect(truePeak["channels"]?.array?[0]["truePeak"]?.double.map { abs($0 - 1.2) < 0.0001 } == true)
        #expect(truePeak["channels"]?.array?[1]["truePeak"]?.double.map { abs($0 - 1.05) < 0.0001 } == true)
    }

    // MARK: 5-6. Measured silence is a zero; no frames is a null

    /// **The contractual distinction.** A silent file was measured and reports a genuine `0`; a file
    /// with no frames has no maximum and reports an explicit `null`. Collapsing them would lose exactly
    /// what the domain type refuses to lose.
    @Test func measuredSilenceExportsAGenuineZeroNeverNull() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([0.0, 0.0]))
        let truePeak = try #require(object["measurements"]?["truePeak"])

        // A genuine, computed zero — present as a number, and specifically **not** null.
        #expect(truePeak["overall"]?.double == 0)
        #expect(truePeak["overall"] != JSONValue.null)
        #expect(truePeak["channels"]?.array?[0]["truePeak"]?.double == 0)
        #expect(truePeak["channels"]?.array?[0]["truePeak"] != JSONValue.null)
        #expect(truePeak["channels"]?.array?[0]["sampleCount"]?.int == 44_100)
    }

    @Test func zeroFramesExportsExplicitNullNeverAFabricatedZero() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([nil, nil]))
        let truePeak = try #require(object["measurements"]?["truePeak"])

        // Present **and** null — not omitted, which a consumer could not distinguish from an older
        // document that never carried the field.
        #expect(truePeak["overall"] == JSONValue.null)
        let channels = try #require(truePeak["channels"]?.array)
        #expect(channels[0]["truePeak"] == JSONValue.null)
        #expect(channels[0]["sampleCount"]?.int == 0, "the frame count is what tells the two zeros apart")
    }

    /// One channel measured beside one that carried nothing: the overall value is the measured one, and
    /// the empty channel is `null` rather than dragging the maximum to zero.
    @Test func anEmptyChannelBesideAMeasuredOneKeepsBothTruths() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([nil, 0.7]))
        let truePeak = try #require(object["measurements"]?["truePeak"])

        #expect(truePeak["overall"]?.double.map { abs($0 - 0.7) < 0.0001 } == true)
        #expect(truePeak["channels"]?.array?[0]["truePeak"] == JSONValue.null)
        #expect(truePeak["channels"]?.array?[1]["truePeak"]?.double.map { abs($0 - 0.7) < 0.0001 } == true)
    }

    // MARK: 7-8. The method describes the measurement that happened

    @Test func theMethodCarriesTheFactorAndTheFilterIdentifier() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([0.5]))
        let method = try #require(object["measurements"]?["truePeak"]?["method"])

        #expect(method["oversamplingFactor"]?.int == 8)
        #expect(method["filter"]?.string == "polyphase_fir_v1")
    }

    /// The values come from the **measurement's own** record, not from a constant in the mapper — so a
    /// document always describes the methodology that actually ran.
    @Test func theMethodFollowsTheMeasurementRatherThanAHardcodedConstant() throws {
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 10, truePeak: 0.5))
        let other = try method(factor: 4, filter: TruePeakFilterIdentifier(rawValue: "some-future-design"))
        let measured = try #require(TruePeakMeasurement(channels: [channel], method: other))

        let method = try #require(
            try exportValue(report(status: .completed), truePeak: measured)["measurements"]?["truePeak"]?["method"]
        )
        #expect(method["oversamplingFactor"]?.int == 4)
        #expect(method["filter"]?.string == "some-future-design")
    }

    /// The filter is an **identity**, not a recipe: nothing that would let a consumer rebuild the DSP,
    /// and no claim of conformance to a standard whose coefficients this project does not use.
    @Test func theMethodExportsNoDesignParametersAndNoComplianceClaim() throws {
        let data = try exportData(report(status: .completed), truePeak: try measurement([1.2]))
        let json = try #require(String(data: data, encoding: .utf8))
        for forbidden in ["taps", "beta", "kaiser", "cutoff", "coefficient", "bs1770", "bs.1770", "ebu", "r128", "compliant"] {
            #expect(!json.lowercased().contains(forbidden), "“\(forbidden)” reached the wire")
        }
    }

    // MARK: 9. The wire is linear — never dBTP

    /// **The unit gate.** The screen shows `-6.02 dBTP` for the same number the wire must carry as
    /// `0.5`. A decibel value here would be a different measurement under the same key.
    @Test func theWireCarriesLinearAmplitudeAndNeverDecibels() throws {
        for (linear, label) in [(Float(1.0), "1.0"), (Float(0.5), "0.5"), (Float(1.2), "1.2")] {
            let object = try exportValue(report(status: .completed), truePeak: try measurement([linear]))
            let overall = try #require(object["measurements"]?["truePeak"]?["overall"]?.double)
            #expect(abs(overall - Double(linear)) < 0.0001, "\(label) was not exported as itself")
            #expect(overall > 0, "a decibel value would be negative here for \(label)")
        }
        // And no unit string travels with it: the contract states the unit, the document does not.
        let data = try exportData(report(status: .completed), truePeak: try measurement([0.5]))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("dBTP"))
        #expect(!json.contains("dBFS"))
        #expect(!json.contains("-6.02"))
    }

    // MARK: 10-11. Absence

    /// No measurement, no key — never `"truePeak": null`, which a consumer could not tell apart from a
    /// measurement that failed to encode.
    @Test func anAbsentMeasurementOmitsTheKeyEntirely() throws {
        let object = try exportValue(report(status: .completed), signalLevelMetrics: signalLevels())
        let measurements = try #require(object["measurements"])
        #expect(measurements["signalLevels"] != nil)
        #expect(measurements["truePeak"] == nil, "an absent measurement appeared as a key")
    }

    /// With neither measurement present, `measurements` itself is omitted — the rule `signalLevels`
    /// established, unchanged by adding a sibling.
    @Test func neitherMeasurementOmitsTheWholeObject() throws {
        let object = try exportValue(report(status: .completed))
        #expect(object["measurements"] == nil)
    }

    /// **Byte-identity**: a report exported without a true peak is exactly what it was before this
    /// capability existed. The strongest form the "additive" rule can take.
    @Test func exportIsByteIdenticalWithAndWithoutTruePeakWhenItIsAbsent() throws {
        let subject = report(status: .completed)
        #expect(try exportData(subject) == (try exportData(subject, truePeak: nil)))
        #expect(
            try exportData(subject, signalLevelMetrics: signalLevels())
                == (try exportData(subject, signalLevelMetrics: signalLevels(), truePeak: nil))
        )
    }

    // MARK: 12. Coexistence with signal levels

    /// Both measurements, side by side, neither nested in nor derived from the other — and **no
    /// aggregate** over them, because nothing downstream should be able to ask a question about the
    /// measurements together.
    @Test func bothMeasurementsCoexistAsSiblings() throws {
        let object = try exportValue(
            report(status: .completed), signalLevelMetrics: signalLevels(), truePeak: try measurement([1.2])
        )
        let measurements = try #require(object["measurements"])

        #expect(try #require(measurements.keys).sorted() == ["signalLevels", "truePeak"])
        #expect(measurements["signalLevels"]?["truePeak"] == nil)
        #expect(measurements["truePeak"]?["signalLevels"] == nil)
        #expect(measurements["truePeak"]?["peakSample"] == nil, "a signal-levels field leaked into true peak")
        #expect(measurements["signalLevels"]?["method"] == nil, "the method was hoisted out of its own measurement")
    }

    /// Exporting a true peak changes **not one byte** of the signal levels object beside it.
    @Test func addingTruePeakLeavesTheSignalLevelsObjectUntouched() throws {
        let without = try exportValue(report(status: .completed), signalLevelMetrics: signalLevels())
        let with = try exportValue(
            report(status: .completed), signalLevelMetrics: signalLevels(), truePeak: try measurement([1.2])
        )
        #expect(without["measurements"]?["signalLevels"] == with["measurements"]?["signalLevels"])
    }

    /// True peak alone, with no signal levels: the object exists with only its own key.
    @Test func truePeakAloneIsRepresentableWithoutSignalLevels() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([0.5]))
        let measurements = try #require(object["measurements"])
        #expect(try #require(measurements.keys).sorted() == ["truePeak"])
    }

    // MARK: 13. Nothing else moves

    @Test func addingTruePeakChangesNoExistingField() throws {
        let subject = report(status: .completed)
        let without = try exportValue(subject)
        let with = try exportValue(subject, truePeak: try measurement([1.2]))

        for key in ["schemaVersion", "generatedAt", "generator", "inspectedFile", "technicalProperties", "warnings", "inspectionStatus"] {
            #expect(without[key] == with[key], "adding a true peak changed \(key)")
        }
    }

    @Test func technicalPropertiesNeverContainsTheMeasurement() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([1.2]))
        let properties = try #require(object["technicalProperties"])
        for key in try #require(properties.keys) {
            #expect(!key.lowercased().contains("truepeak"), "a DSP measurement was smuggled into technicalProperties")
        }
        #expect(properties["truePeak"] == nil)
        // And it is not hoisted into the report envelope either.
        #expect(object["method"] == nil)
    }

    // MARK: 14. Privacy

    @Test func noPathOrFilesystemMetadataLeaksThroughTheMeasurement() throws {
        let data = try exportData(report(status: .completed), truePeak: try measurement([1.2, 0.5]))
        let json = try #require(String(data: data, encoding: .utf8))
        for forbidden in ["/Users/", "file://", "bookmark", "securityScope", ".wav\\/"] {
            #expect(!json.contains(forbidden), "“\(forbidden)” reached the wire")
        }
        let exported = try exportValue(report(status: .completed), truePeak: try measurement([0.5]))
        let keys = try #require(exported["measurements"]?["truePeak"]?.keys)
        for forbidden in ["path", "url", "bookmark", "directory", "filename"] {
            #expect(!keys.contains { $0.lowercased().contains(forbidden) }, "“\(forbidden)” is a key in the export")
        }
    }

    // MARK: 15. Determinism and the version

    @Test func theSameMeasurementExportsByteIdenticalDataTwice() throws {
        let measured = try measurement([1.2, 0.5])
        let subject = report(status: .completed)
        #expect(
            try exportData(subject, signalLevelMetrics: signalLevels(), truePeak: measured)
                == (try exportData(subject, signalLevelMetrics: signalLevels(), truePeak: measured))
        )
    }

    @Test func schemaVersionStaysOneWithTruePeakPresent() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([1.2]))
        #expect(object["schemaVersion"]?.int == 1, "an additive measurement bumped the schema version")
    }

    /// The keys are exactly the documented ones — nothing extra rides along.
    @Test func truePeakUsesExactlyTheDocumentedKeys() throws {
        let object = try exportValue(report(status: .completed), truePeak: try measurement([0.5, nil]))
        let truePeak = try #require(object["measurements"]?["truePeak"])
        #expect(try #require(truePeak.keys).sorted() == ["channels", "method", "overall"])

        let channel = try #require(truePeak["channels"]?.array?.first)
        #expect(try #require(channel.keys).sorted() == ["sampleCount", "truePeak"])

        let method = try #require(truePeak["method"])
        #expect(try #require(method.keys).sorted() == ["filter", "oversamplingFactor"])
    }
}
