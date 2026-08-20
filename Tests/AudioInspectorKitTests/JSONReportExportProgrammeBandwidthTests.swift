import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp

/// The wire contract for `measurements.programmeBandwidth` — a fourth sibling under the same additive
/// rule `signalLevels` established and `truePeak` and `integratedLoudness` reused, added without a
/// `schemaVersion` bump.
///
/// Everything is asserted through `Codable`/`JSONDecoder` over the real exporter, never through
/// `JSONSerialization` and never against a hand-written string, so these tests describe the document a
/// consumer actually receives.
///
/// **The document exports the measurement, and only the measurement.** Not the interpretation, not a
/// suspicion, not a supposed cause, and not a form of the number made more comfortable for a person to
/// read — that last one has its own test, because it is the one a well-meaning change would break.
@Suite("Export — measurements.programmeBandwidth (schemaVersion 1, additive)")
struct JSONReportExportProgrammeBandwidthTests {

    // MARK: - Fixtures

    private func bandwidth(
        channels: [Double?] = [16_101.5625],
        resolution: Double = 23.4375,
        windowFrames: Int = 2_048,
        rate: Double = 48_000,
        identifier: String = SignificantBandwidthMethod.v1
    ) throws -> SignificantBandwidth {
        let method = try #require(SignificantBandwidthMethod(
            identifier: identifier, windowFrames: windowFrames,
            hopFrames: windowFrames / 4, sampleRate: rate
        ))
        let readings: [SignificantBandwidth.Channel?] = try channels.map { frequency in
            guard let frequency else { return nil }
            return try #require(SignificantBandwidth.Channel(frequency: frequency, resolution: resolution))
        }
        return try #require(SignificantBandwidth(channels: readings, method: method))
    }

    private func truePeak() throws -> TruePeakMeasurement {
        let method = try #require(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1))
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 44_100, truePeak: 0.5))
        return try #require(TruePeakMeasurement(channels: [channel], method: method))
    }

    private func loudness() throws -> LoudnessMeasurement {
        try #require(LoudnessMeasurement(
            integratedLoudness: -23.0,
            method: LoudnessMethod(algorithm: .integratedBS1770v1, weighting: .publishedAt48kHz)
        ))
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

    private func measurementObject(
        _ model: SignificantBandwidth, in report: InspectionReport? = nil
    ) throws -> JSONValue {
        let json = try exportValue(report ?? subject, programmeBandwidth: model)
        return try #require(json["measurements"]?["programmeBandwidth"], "the key is missing")
    }

    private let subject = report(status: .completed)

    // MARK: 1. The object and its key

    /// **The key names the measurement, not an inference.** `cutoff` and `frequencyLimit` would assert a
    /// filter nobody observed; `effectiveSampleRate` would assert the file should have been stored
    /// differently; `significantBandwidth` is the domain type's name where the product's belongs.
    @Test func programmeBandwidthIsItsOwnSiblingUnderMeasurements() throws {
        let json = try exportValue(subject, programmeBandwidth: try bandwidth())
        let measurements = try #require(json["measurements"])
        #expect(measurements["programmeBandwidth"] != nil)
        #expect(measurements["significantBandwidth"] == nil, "the domain's own name reached the wire")
        #expect(measurements["cutoff"] == nil)
        #expect(measurements["frequencyLimit"] == nil)
        #expect(measurements["effectiveSampleRate"] == nil)
    }

    @Test func programmeBandwidthUsesExactlyTheDocumentedKeys() throws {
        let object = try measurementObject(try bandwidth())
        #expect(try #require(object.keys) == ["overall", "channels", "method"])
        let method = try #require(object["method"])
        #expect(try #require(method.keys) == ["identifier", "windowFrames", "hopFrames", "sampleRate"])
        let overall = try #require(object["overall"])
        #expect(try #require(overall.keys) == ["frequency", "resolution"])
    }

    // MARK: 2. Units and precision

    /// **Hertz, as the domain's own unrounded `Double`.** The screen shows `16.1 kHz` because a
    /// displayed digit must correspond to a distinction the analysis can make; the wire carries the
    /// datum. This asserts the two are *different*, which is the property a change that "tidied up" the
    /// exported number would break.
    @Test func theWireCarriesFullPrecisionHertzAndNotTheDisplayedValue() throws {
        let object = try measurementObject(try bandwidth())
        let overall = try #require(object["overall"])
        #expect(overall["frequency"]?.double == 16_101.5625)
        #expect(overall["resolution"]?.double == 23.4375)
        // The value the surface shows, rounded to a 100 Hz step, is deliberately *not* what travels.
        #expect(overall["frequency"]?.double != 16_100)
        #expect(overall["frequency"]?.double != 16.1)
    }

    /// No unit strings, no kilohertz, and nothing stringly typed: this contract states the unit, the
    /// document does not carry one — the rule `integratedLoudness` already follows.
    @Test func nothingIsAStringAndNoUnitTravels() throws {
        let object = try measurementObject(try bandwidth())
        let overall = try #require(object["overall"])
        #expect(overall["frequency"]?.string == nil, "the frequency travelled as text")
        #expect(overall["resolution"]?.string == nil, "the resolution travelled as text")
        for key in allKeys(object) where key.lowercased().contains("khz") {
            Issue.record("a kilohertz key reached the wire: \(key)")
        }
    }

    /// **`resolution` is a bin width and never an interval.** There is no `±`, no `uncertainty`, no
    /// `error`, no `tolerance` and no `margin` — ADR-0023 refuses to publish a false bound, and the
    /// reading is biased one way, so a symmetric interval would be wrong in shape as well as in kind.
    @Test func theResolutionIsItsOwnFieldAndNeverAnUncertainty() throws {
        let object = try measurementObject(try bandwidth())
        let keys = allKeys(object).map { $0.lowercased() }
        for forbidden in ["uncertainty", "error", "tolerance", "margin", "plusminus", "interval", "confidence", "accuracy"] {
            #expect(!keys.contains(where: { $0.contains(forbidden) }), "\(forbidden) reached the wire")
        }
        let data = try exportData(subject, programmeBandwidth: try bandwidth())
        #expect(!String(decoding: data, as: UTF8.self).contains("±"))
    }

    // MARK: 3. The method

    /// Copied from the measurement's own record, field for field.
    @Test func theMethodIsCopiedFromTheMeasurement() throws {
        let model = try bandwidth(windowFrames: 1_920, rate: 44_100)
        let method = try #require(try measurementObject(model)["method"])
        #expect(method["identifier"]?.string == SignificantBandwidthMethod.v1)
        #expect(method["windowFrames"]?.int == 1_920)
        #expect(method["hopFrames"]?.int == 480)
        #expect(method["sampleRate"]?.double == 44_100)
    }

    /// **The mapper does not reconstruct the method from the sample rate.** A measurement carrying an
    /// unusual identity exports that identity verbatim — a document that inferred it could describe a
    /// methodology that never ran.
    @Test func theMethodFollowsTheMeasurementRatherThanTheSampleRate() throws {
        let model = try bandwidth(windowFrames: 4_096, rate: 48_000, identifier: "programme-bandwidth-experimental-v9")
        let method = try #require(try measurementObject(model)["method"])
        #expect(method["identifier"]?.string == "programme-bandwidth-experimental-v9")
        // 48 kHz would have selected 2048 had the mapper derived it; it exports what ran.
        #expect(method["windowFrames"]?.int == 4_096)
    }

    /// The identifier stands for the whole rule set, so the constants behind it are **not** duplicated
    /// as fields: emitting them as data would invite a consumer to believe some other combination was
    /// possible, when the identifier is precisely what says it was not.
    ///
    /// Asserted as an exact key set rather than by sweeping for words — `windowFrames` legitimately
    /// contains "window", and a substring sweep would either miss the real case or reject the honest
    /// one. The constants are then checked as *values*, which is the form they would actually leak in.
    @Test func theMethodExportsNoLooseConstants() throws {
        let method = try #require(try measurementObject(try bandwidth())["method"])
        #expect(try #require(method.keys) == ["identifier", "windowFrames", "hopFrames", "sampleRate"])

        let text = String(decoding: try exportData(subject, programmeBandwidth: try bandwidth()), as: UTF8.self)
        for constant in ["-50", "0.1", "0.003162", "0.001", "60", "hann", "Hann"] {
            #expect(
                !text.contains("\"\(constant)\""),
                "the rule set's \(constant) was exported as a value rather than standing behind the identifier"
            )
        }
        // The identifier is the one place the rule set is named, and it names it as a version.
        #expect(method["identifier"]?.string == "programme-bandwidth-60db-v1")
    }

    // MARK: 4. Channels

    /// One entry per channel in the stream's own order, `null` where that channel carried nothing —
    /// the position is the channel index, so an entry cannot be dropped without renumbering the rest.
    @Test func channelsKeepTheirIndexAndNullWhereThereIsNoReading() throws {
        let object = try measurementObject(try bandwidth(channels: [16_101.5625, nil, 20_015.625]))
        let channels = try #require(object["channels"]?.array)
        #expect(channels.count == 3)
        #expect(channels[0]["frequency"]?.double == 16_101.5625)
        #expect(channels[1] == .null, "a channel with no reading was not null")
        #expect(channels[2]["frequency"]?.double == 20_015.625)
    }

    /// `overall` is the highest of the per-channel readings — a summary of the facts beside it, and no
    /// layout is named anywhere.
    @Test func overallIsTheHighestReadingAndNoLayoutIsNamed() throws {
        let object = try measurementObject(try bandwidth(channels: [16_101.5625, 20_015.625]))
        #expect(object["overall"]?["frequency"]?.double == 20_015.625)
        let keys = allKeys(object).map { $0.lowercased() }
        for layout in ["left", "right", "centre", "center", "stereo", "mono", "lfe"] {
            #expect(!keys.contains(layout), "a channel layout was named: \(layout)")
        }
    }

    // MARK: 5. Absence

    /// **Absence is the key not being there** — never `null`, never a zero, never Nyquist, never an
    /// empty object.
    @Test func anAbsentMeasurementOmitsTheKeyEntirely() throws {
        let json = try exportValue(subject, programmeBandwidth: nil)
        #expect(json["measurements"] == nil)
        let withSibling = try exportValue(subject, truePeak: try truePeak(), programmeBandwidth: nil)
        let measurements = try #require(withSibling["measurements"])
        #expect(measurements["programmeBandwidth"] == nil)
        #expect(try #require(measurements.keys) == ["truePeak"])
    }

    /// A report with no measurement at all still carries no `measurements` object — adding a fourth
    /// optional key did not make the object appear.
    @Test func noMeasurementAtAllOmitsTheWholeObject() throws {
        #expect(try exportValue(subject)["measurements"] == nil)
    }

    /// **Byte-identity**: a report exported without programme bandwidth is byte-identical to one from
    /// before the key existed, which is what "additive" has to mean.
    @Test func exportIsByteIdenticalWithoutProgrammeBandwidth() throws {
        let withOthers = try exportData(subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak())
        let withExplicitNil = try exportData(
            subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak(), programmeBandwidth: nil
        )
        #expect(withOthers == withExplicitNil)
    }

    // MARK: 6. schemaVersion and coexistence

    @Test func theSchemaVersionStaysOne() throws {
        #expect(try exportValue(subject, programmeBandwidth: try bandwidth())["schemaVersion"]?.int == 1)
        #expect(try exportValue(subject)["schemaVersion"]?.int == 1)
    }

    @Test func programmeBandwidthAloneIsRepresentableWithoutItsSiblings() throws {
        let measurements = try #require(
            try exportValue(subject, programmeBandwidth: try bandwidth())["measurements"]
        )
        #expect(try #require(measurements.keys) == ["programmeBandwidth"])
    }

    @Test func allFourMeasurementsCoexistAsSiblings() throws {
        let json = try exportValue(
            subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak(),
            loudness: try loudness(), programmeBandwidth: try bandwidth()
        )
        let measurements = try #require(json["measurements"])
        #expect(
            try #require(measurements.keys)
                == ["signalLevels", "truePeak", "integratedLoudness", "programmeBandwidth"]
        )
    }

    /// Adding the fourth changed none of the three before it, nor any envelope field.
    @Test func addingProgrammeBandwidthLeavesEverythingElseUntouched() throws {
        let without = try exportValue(
            subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak(), loudness: try loudness()
        )
        let with = try exportValue(
            subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak(),
            loudness: try loudness(), programmeBandwidth: try bandwidth()
        )
        for key in ["signalLevels", "truePeak", "integratedLoudness"] {
            #expect(with["measurements"]?[key] == without["measurements"]?[key], "\(key) changed")
        }
        for key in ["schemaVersion", "generatedAt", "generator", "inspectedFile", "technicalProperties", "warnings", "inspectionStatus"] {
            #expect(with[key] == without[key], "\(key) changed")
        }
    }

    // MARK: 7. Determinism and privacy

    @Test func twoExportsOfTheSameInputAreByteIdentical() throws {
        let model = try bandwidth(channels: [16_101.5625, 20_015.625])
        let first = try exportData(subject, programmeBandwidth: model)
        let second = try exportData(subject, programmeBandwidth: model)
        #expect(first == second)
    }

    /// The measurement introduces no path, no URL, no filename, no bookmark, no decoder detail and no
    /// tool name. The method identity is a fact about the analysis; where the file lives is not.
    @Test func noPathOrToolMetadataLeaksThroughTheMeasurement() throws {
        let object = try measurementObject(try bandwidth())
        let keys = allKeys(object).map { $0.lowercased() }
        for forbidden in ["path", "url", "file", "filename", "bookmark", "directory", "volume",
                          "decoder", "ffmpeg", "avfoundation", "codec", "container", "temp"] {
            #expect(!keys.contains(where: { $0.contains(forbidden) }), "\(forbidden) reached the wire")
        }
        let text = String(decoding: try exportData(subject, programmeBandwidth: try bandwidth()), as: UTF8.self)
        for forbidden in ["/Users/", "file://", ".wav", "ffmpeg", "AVFoundation"] {
            #expect(!text.contains(forbidden), "\(forbidden) appeared in the document")
        }
    }

    /// **The wire is factual, exactly as the surface is.** No field expresses a conclusion, a suspicion
    /// or a cause, and none exists to be filled in later.
    ///
    /// Swept over the measurement's own keys with **whole-word** matching, because the envelope has
    /// legitimate neighbours a substring sweep would trip over — `warnings` is a pre-existing field and
    /// contains "warning". The words that could never be legitimate anywhere are swept over the whole
    /// document as well.
    @Test func noKeyExpressesAVerdictOrACause() throws {
        let object = try measurementObject(try bandwidth())
        let words = Set(allKeys(object).flatMap { splitCamelCase($0) })
        for forbidden in ["upsampled", "upsampling", "transcode", "transcoded", "suspicious", "detected",
                          "inferred", "codec", "quality", "genuine", "confidence", "finding", "verdict",
                          "likely", "probable", "score", "rating", "warning", "cutoff", "real", "true"] {
            #expect(!words.contains(forbidden), "\(forbidden) reached the measurement's keys")
        }

        let whole = try exportValue(
            subject, signalLevelMetrics: try signalLevels(), truePeak: try truePeak(),
            loudness: try loudness(), programmeBandwidth: try bandwidth()
        )
        let everyWord = Set(allKeys(whole).flatMap { splitCamelCase($0) })
        for forbidden in ["upsampled", "transcode", "suspicious", "cutoffdetected", "inferredcodec",
                          "verdict", "finding", "confidence", "sourceresolution"] {
            #expect(!everyWord.contains(forbidden), "\(forbidden) reached the document")
        }
    }

    /// Splits a camelCase key into its lowercased words, so `windowFrames` is `["window", "frames"]`
    /// and never matches a sweep for a word it merely contains part of.
    private func splitCamelCase(_ key: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in key {
            if character.isUppercase, !current.isEmpty {
                words.append(current.lowercased()); current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        return words
    }
}
