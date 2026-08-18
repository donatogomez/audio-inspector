import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp

/// The wire contract for `measurements.integratedLoudness` — a third sibling under the same additive
/// rule `signalLevels` established and `truePeak` reused, added without a `schemaVersion` bump.
///
/// Everything is asserted through `Codable`/`JSONDecoder` over the real exporter, never through
/// `JSONSerialization` and never against a hand-written string, so these tests describe the document a
/// consumer actually receives.
@Suite("Export — measurements.integratedLoudness (schemaVersion 1, additive)")
struct JSONReportExportLoudnessTests {

    // MARK: - Fixtures

    private func loudness(
        _ lufs: Double,
        weighting: LoudnessWeightingIdentifier = .publishedAt48kHz,
        algorithm: LoudnessAlgorithmIdentifier = .integratedBS1770v1
    ) throws -> LoudnessMeasurement {
        try #require(LoudnessMeasurement(
            integratedLoudness: lufs,
            method: LoudnessMethod(algorithm: algorithm, weighting: weighting)
        ))
    }

    private func truePeak() throws -> TruePeakMeasurement {
        let method = try #require(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1))
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 44_100, truePeak: 0.5))
        return try #require(TruePeakMeasurement(channels: [channel], method: method))
    }

    private func signalLevels() throws -> SignalLevelMetrics {
        let channel = try #require(SignalLevelMetrics.Channel(
            sampleCount: 44_100, peakSample: 0.5, rms: 0.25, dcOffset: 0.001, clippedSampleCount: 0
        ))
        return try #require(SignalLevelMetrics(
            channels: [channel],
            overallPeakSample: 0.5, overallRMS: 0.25, overallDCOffset: 0.001, overallClippedSampleCount: 0
        ))
    }

    // MARK: 1. The object and its key

    /// **The key names the quantity, not the family.** `loudness` would cover four different
    /// measurements — momentary, short-term and loudness range are not this one — and a `method` inside
    /// such an object would imply it described them all.
    @Test func integratedLoudnessIsItsOwnSiblingUnderMeasurements() throws {
        let object = try exportValue(report(status: .completed), loudness: try loudness(-23.0139))
        let measured = try #require(object["measurements"]?["integratedLoudness"])

        #expect(measured["value"]?.double == -23.0139)
        // Its own object under `measurements`, never nested in a sibling and never hoisted.
        #expect(object["integratedLoudness"] == nil)
        #expect(object["loudness"] == nil)
        #expect(object["measurements"]?["loudness"] == nil)
        #expect(object["measurements"]?["truePeak"]?["integratedLoudness"] == nil)
    }

    /// The keys are exactly the documented ones — nothing extra rides along. In particular **no
    /// `channels`**: the channels are combined before this quantity exists.
    @Test func integratedLoudnessUsesExactlyTheDocumentedKeys() throws {
        let object = try exportValue(report(status: .completed), loudness: try loudness(-23.0))
        let measured = try #require(object["measurements"]?["integratedLoudness"])
        #expect(try #require(measured.keys).sorted() == ["method", "value"])

        let method = try #require(measured["method"])
        #expect(try #require(method.keys).sorted() == ["algorithm", "weighting"])
    }

    // MARK: 2. The unit on the wire is LUFS — and the value is unrounded

    /// **The unit gate, and it points the opposite way from true peak's.** That measurement exports
    /// linear because dBTP is a presentation of a linear peak; here the logarithmic quantity is the
    /// normative one, so LUFS is what travels. Exporting energy would invent a unit the standard does
    /// not use.
    @Test func theWireCarriesLUFSAndNeverLinearEnergy() throws {
        for lufs in [-23.0139, -18.4, 0.0, 2.1436] {
            let object = try exportValue(report(status: .completed), loudness: try loudness(lufs))
            #expect(object["measurements"]?["integratedLoudness"]?["value"]?.double == lufs)
        }
        // A linear energy for −23.0139 LUFS would be ≈ 0.0037 — small, positive, and nothing like the
        // value above. Pinning the sign and magnitude catches a conversion slipped in at this layer.
        let negative = try #require(
            try exportValue(report(status: .completed), loudness: try loudness(-23.0139))["measurements"]?["integratedLoudness"]?["value"]?.double
        )
        #expect(negative < -20, "the value looks like linear energy rather than LUFS")
    }

    /// **The screen's one decimal never reaches the wire.** `-23.0139` is exported as itself; the
    /// display precision is a presentation concern applied in `FeatureAnalysis`, which this layer does
    /// not import.
    @Test func theValueIsUnroundedAndCarriesNoUnitString() throws {
        let data = try exportData(report(status: .completed), loudness: try loudness(-23.0139))
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("-23.0139"))
        #expect(!json.contains("-23.0 LUFS"))
        #expect(!json.contains("LUFS"), "a unit string travelled with the number")
        #expect(!json.contains("LKFS"))
        #expect(!json.contains("dBFS"))
        #expect(!json.contains("dBTP"))
    }

    /// A programme above full scale exports exactly as measured, unclamped — the rule the screen
    /// follows, on the wire.
    @Test func aPositiveValueExportsExactlyAsMeasured() throws {
        let object = try exportValue(report(status: .completed), loudness: try loudness(2.1436))
        #expect(object["measurements"]?["integratedLoudness"]?["value"]?.double == 2.1436)
    }

    // MARK: 3. The method describes the measurement that happened

    @Test func theMethodCarriesBothIdentitiesForAPublishedWeighting() throws {
        let object = try exportValue(report(status: .completed), loudness: try loudness(-23.0))
        let method = try #require(object["measurements"]?["integratedLoudness"]?["method"])

        #expect(method["algorithm"]?.string == "itu_r_bs1770_5_integrated_v1")
        #expect(method["weighting"]?.string == "itu_r_bs1770_5_tables_1_2_48k")
    }

    /// The rate other than 48 kHz, where the coefficients were derived rather than transcribed. **The
    /// two are distinguishable on the wire**, which is the whole reason the identity exists — and the
    /// reason the screen does not need to show it.
    @Test func theMethodCarriesTheDerivedWeightingWhenThatIsWhatRan() throws {
        let object = try exportValue(
            report(status: .completed), loudness: try loudness(-23.0, weighting: .derivedFrom48kHz)
        )
        let method = try #require(object["measurements"]?["integratedLoudness"]?["method"])

        #expect(method["weighting"]?.string == "itu_r_bs1770_5_48k_prototype_rediscretised_v1")
        #expect(method["weighting"]?.string != "itu_r_bs1770_5_tables_1_2_48k")
        // The algorithm is unchanged by the rate: only the filter's provenance differs.
        #expect(method["algorithm"]?.string == "itu_r_bs1770_5_integrated_v1")
    }

    /// **The mapper serialises what the measurement carries and infers nothing.** A document that chose
    /// its weighting from a sample rate could describe a methodology that never ran — and the
    /// measurement carries no sample rate to choose from in the first place.
    @Test func theMethodFollowsTheMeasurementRatherThanAHardcodedConstant() throws {
        let measured = try loudness(
            -23.0,
            weighting: LoudnessWeightingIdentifier(rawValue: "some-future-weighting"),
            algorithm: LoudnessAlgorithmIdentifier(rawValue: "some-future-algorithm")
        )
        let method = try #require(
            try exportValue(report(status: .completed), loudness: measured)["measurements"]?["integratedLoudness"]?["method"]
        )
        #expect(method["algorithm"]?.string == "some-future-algorithm")
        #expect(method["weighting"]?.string == "some-future-weighting")
    }

    /// The method is an **identity, not a configuration**: no block length, no hop, no gate threshold,
    /// no coefficients. A consumer is told which methodology ran, not how to re-run one.
    @Test func theMethodExportsNoConstantsAndNoDesignParameters() throws {
        let data = try exportData(report(status: .completed), loudness: try loudness(-23.0))
        let json = try #require(String(data: data, encoding: .utf8))
        for forbidden in ["blockLength", "hop", "gate", "threshold", "coefficient", "offset", "-0.691"] {
            #expect(!json.lowercased().contains(forbidden.lowercased()), "“\(forbidden)” reached the wire")
        }
    }

    // MARK: 4. No verdict, no target, no compliance, no oracle

    /// The vocabulary this measurement attracts, swept over the whole document — the wire equivalent of
    /// the surface's own sweep, and the reason `compliant: true` can never quietly appear.
    @Test func nothingOnTheWireClaimsComplianceOrQuotesATarget() throws {
        let data = try exportData(
            report(status: .completed), signalLevelMetrics: try signalLevels(), truePeak: try truePeak(),
            loudness: try loudness(-23.0139)
        )
        let json = try #require(String(data: data, encoding: .utf8))
        let forbidden = [
            "compliant", "compliance", "conformant", "conformance", "certified", "certification",
            "ebu mode", "ebumode", "pass", "target", "recommended", "normalise", "normalize",
            "spotify", "apple music", "youtube", "tooLoud", "verdict",
        ]
        for token in forbidden {
            #expect(!json.lowercased().contains(token.lowercased()), "“\(token)” reached the wire")
        }
    }

    /// **The oracle is a test-time instrument and never a fact about a file.** No FFmpeg, no observed
    /// tolerance, no agreement figure: those are evidence about this implementation, gathered while
    /// qualifying it, not properties of the audio someone exported.
    @Test func noOracleOrToleranceMetadataReachesTheWire() throws {
        let data = try exportData(report(status: .completed), loudness: try loudness(-23.0139))
        let json = try #require(String(data: data, encoding: .utf8))
        for token in ["ffmpeg", "ebur128", "libebur128", "oracle", "tolerance", "agreement", "reference"] {
            #expect(!json.lowercased().contains(token), "“\(token)” reached the wire")
        }
        // Nor as a key anywhere in the document, which a substring sweep over a version string could
        // not distinguish: `generator.version` legitimately contains digits.
        let object = try exportValue(report(status: .completed), loudness: try loudness(-23.0139))
        for key in allKeys(object) {
            for token in ["oracle", "tolerance", "agreement", "verified", "validated"] {
                #expect(!key.lowercased().contains(token), "“\(key)” is a key in the export")
            }
        }
    }

    /// The file's shape is `technicalProperties`' business. Repeating it inside the measurement would be
    /// a second description this document could not keep consistent with the first — which is exactly
    /// why `LoudnessMeasurement` carries neither.
    @Test func theMeasurementRepeatsNoFilePropertyOfItsOwn() throws {
        let object = try exportValue(report(status: .completed), loudness: try loudness(-23.0))
        let measured = try #require(object["measurements"]?["integratedLoudness"])
        for key in ["channelCount", "sampleRate", "channels", "duration", "frameCount"] {
            #expect(measured[key] == nil, "“\(key)” was duplicated into the measurement")
        }
        // And the properties are untouched by the measurement existing.
        let properties = try #require(object["technicalProperties"])
        for key in try #require(properties.keys) {
            #expect(!key.lowercased().contains("loudness"), "a DSP measurement was smuggled into technicalProperties")
        }
    }

    // MARK: 5. Absence

    /// No measurement, no key — **never `"integratedLoudness": null`**, which a consumer could not tell
    /// apart from a measurement that failed to encode. Every cause of an absence collapses to the same
    /// thing here: the document describes measurements, not why one does not exist.
    @Test func anAbsentMeasurementOmitsTheKeyEntirely() throws {
        let object = try exportValue(report(status: .completed), truePeak: try truePeak())
        let measurements = try #require(object["measurements"])
        #expect(measurements["truePeak"] != nil)
        #expect(measurements["integratedLoudness"] == nil, "an absent measurement appeared as a key")
        #expect(measurements["integratedLoudness"] != JSONValue.null)
    }

    /// With no measurement at all, `measurements` itself is omitted — the rule `signalLevels`
    /// established, unchanged by adding a third sibling.
    @Test func noMeasurementAtAllOmitsTheWholeObject() throws {
        #expect(try exportValue(report(status: .completed))["measurements"] == nil)
    }

    /// **Byte-identity**: a report exported without a loudness is exactly what it was before this
    /// capability existed. The strongest form the "additive" rule can take.
    @Test func exportIsByteIdenticalWithAndWithoutLoudnessWhenItIsAbsent() throws {
        let subject = report(status: .completed)
        #expect(try exportData(subject) == (try exportData(subject, loudness: nil)))
        #expect(
            try exportData(subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak())
                == (try exportData(
                    subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak(), loudness: nil
                ))
        )
    }

    /// Loudness alone, with neither sibling: the object exists with only its own key.
    @Test func loudnessAloneIsRepresentableWithoutItsSiblings() throws {
        let measurements = try #require(
            try exportValue(report(status: .completed), loudness: try loudness(-23.0))["measurements"]
        )
        #expect(try #require(measurements.keys).sorted() == ["integratedLoudness"])
    }

    // MARK: 6. Coexistence with the two existing siblings

    /// Three measurements side by side, none nested in or derived from another — and **no aggregate**
    /// over them, because nothing downstream should be able to ask a question about them together.
    @Test func allThreeMeasurementsCoexistAsSiblings() throws {
        let object = try exportValue(
            report(status: .completed), signalLevelMetrics: try signalLevels(), truePeak: try truePeak(),
            loudness: try loudness(-23.0139)
        )
        let measurements = try #require(object["measurements"])

        #expect(try #require(measurements.keys).sorted() == ["integratedLoudness", "signalLevels", "truePeak"])
        #expect(measurements["integratedLoudness"]?["overall"] == nil, "a true peak field leaked in")
        #expect(measurements["integratedLoudness"]?["peakSample"] == nil, "a signal-levels field leaked in")
        #expect(measurements["signalLevels"]?["value"] == nil)
        #expect(measurements["truePeak"]?["value"] == nil)
        // The method stays inside its own measurement rather than being hoisted to cover the others.
        #expect(measurements["method"] == nil)
    }

    /// **Exporting a loudness changes not one byte of either sibling beside it.**
    @Test func addingLoudnessLeavesItsSiblingObjectsUntouched() throws {
        let without = try exportValue(
            report(status: .completed), signalLevelMetrics: try signalLevels(), truePeak: try truePeak()
        )
        let with = try exportValue(
            report(status: .completed), signalLevelMetrics: try signalLevels(), truePeak: try truePeak(),
            loudness: try loudness(-23.0139)
        )
        #expect(without["measurements"]?["signalLevels"] == with["measurements"]?["signalLevels"])
        #expect(without["measurements"]?["truePeak"] == with["measurements"]?["truePeak"])
    }

    @Test func addingLoudnessChangesNoExistingEnvelopeField() throws {
        let subject = report(status: .completed)
        let without = try exportValue(subject)
        let with = try exportValue(subject, loudness: try loudness(-23.0139))

        for key in ["schemaVersion", "generatedAt", "generator", "inspectedFile", "technicalProperties", "warnings", "inspectionStatus"] {
            #expect(without[key] == with[key], "adding a loudness changed \(key)")
        }
    }

    // MARK: 7. Privacy

    @Test func noPathOrFilesystemMetadataLeaksThroughTheMeasurement() throws {
        let data = try exportData(report(status: .completed), loudness: try loudness(-23.0139))
        let json = try #require(String(data: data, encoding: .utf8))
        for forbidden in ["/Users/", "file://", "bookmark", "securityScope", "securityScoped"] {
            #expect(!json.contains(forbidden), "“\(forbidden)” reached the wire")
        }
        let object = try exportValue(report(status: .completed), loudness: try loudness(-23.0139))
        let measured = try #require(object["measurements"]?["integratedLoudness"])
        for forbidden in ["path", "url", "bookmark", "directory", "filename", "scope"] {
            let keys = try #require(measured.keys).union(try #require(measured["method"]?.keys))
            #expect(!keys.contains { $0.lowercased().contains(forbidden) }, "“\(forbidden)” is a key in the export")
        }
    }

    // MARK: 8. Determinism and the version

    @Test func theSameMeasurementExportsByteIdenticalDataTwice() throws {
        let measured = try loudness(-23.0139)
        let subject = report(status: .completed)
        #expect(
            try exportData(subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak(), loudness: measured)
                == (try exportData(
                    subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak(), loudness: measured
                ))
        )
    }

    @Test func schemaVersionStaysOneWithLoudnessPresent() throws {
        let object = try exportValue(report(status: .completed), loudness: try loudness(-23.0139))
        #expect(object["schemaVersion"]?.int == 1, "an additive measurement bumped the schema version")

        // And with all three present, which is the fullest document this contract can produce.
        let full = try exportValue(
            report(status: .completed), signalLevelMetrics: try signalLevels(), truePeak: try truePeak(),
            loudness: try loudness(-23.0139)
        )
        #expect(full["schemaVersion"]?.int == 1)
    }
}
