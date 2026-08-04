import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

/// Presentation-logic tests for the report view's property rows. Pure — no SwiftUI, no snapshots.
/// They assert the eight fields exist and that each `Property` state maps to a distinct, honest row
/// (no fabricated values; units only alongside a value).
@Suite("Feature — report property display")
struct ReportPropertyDisplayTests {

    private func mixedProperties() -> TechnicalProperties {
        TechnicalProperties(
            container: .available("wav"),
            duration: .available(10.5),
            sampleRate: .available(44_100),
            channelCount: .unavailable(reason: nil),
            bitDepth: .unsupported(reason: "lossy codec"),
            codec: .uncertain(value: "aac", reason: "inferred"),
            declaredBitrate: .failed(PropertyFailure(code: .propertyReadError, message: "boom")),
            estimatedBitrate: .uncertain(value: nil, reason: "cannot estimate")
        )
    }

    @Test func allEightPropertiesAreRepresentedInOrder() {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())
        #expect(displays.map(\.name) == [
            "Container", "Duration", "Sample rate", "Channel count",
            "Bit depth", "Codec", "Declared bitrate", "Estimated bitrate",
        ])
    }

    @Test func eachStateIsDistinctlyRepresented() {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())
        // Same eight distinctions as before, now as a closed presentation enum instead of free strings.
        #expect(displays.map(\.state) == [
            .measured, .measured, .measured, .notPresent,
            .notDefinedByFormat, .readButUnreliable, .couldNotBeRead, .readButUnreliable,
        ])
    }

    /// Only a cleanly measured value goes unlabelled; every other state says what it is, in words that
    /// describe the reading and never characterise the file.
    @Test func onlyMeasuredValuesCarryNoStateLabel() {
        #expect(PropertyPresentationState.measured.label == nil)
        for state in PropertyPresentationState.allCases where state != .measured {
            let label = state.label
            #expect(label != nil)
            #expect(label?.isEmpty == false)
        }
    }

    @Test func availableRowsCarryValueAndUnitOnlyWhereMeaningful() throws {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())

        let container = try #require(displays.first { $0.name == "Container" })
        #expect(container.value == "wav")
        #expect(container.unit == nil) // container is unitless

        let duration = try #require(displays.first { $0.name == "Duration" })
        #expect(duration.value == "10.5")
        #expect(duration.unit == "seconds")

        let sampleRate = try #require(displays.first { $0.name == "Sample rate" })
        #expect(sampleRate.value == "44100")
        #expect(sampleRate.unit == "hertz")
    }

    @Test func absentStatesCarryNoValueAndNoUnit() throws {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())

        // unavailable → no value, no unit.
        let channels = try #require(displays.first { $0.name == "Channel count" })
        #expect(channels.value == nil)
        #expect(channels.unit == nil)

        // unsupported → no value, reason surfaced.
        let bitDepth = try #require(displays.first { $0.name == "Bit depth" })
        #expect(bitDepth.value == nil)
        #expect(bitDepth.unit == nil)
        #expect(bitDepth.detail == "lossy codec")

        // failed → no value, and the human message only: the stable code stays in the JSON, where it
        // is the contract's identity, not something to read.
        let declared = try #require(displays.first { $0.name == "Declared bitrate" })
        #expect(declared.value == nil)
        #expect(declared.detail == "boom")
        #expect(declared.detail?.contains("property_read_error") == false)
    }

    @Test func uncertainWithValueKeepsUnitButWithoutValueDropsIt() throws {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())

        // uncertain WITH value → value present, unitless field so no unit but reason kept. The codec is
        // now named, and the exact token is preserved in the detail so the summary never hides the datum.
        let codec = try #require(displays.first { $0.name == "Codec" })
        #expect(codec.value == "AAC")
        #expect(codec.unit == nil) // codec is unitless
        #expect(codec.detail == "aac — inferred")

        // uncertain WITHOUT value → no value ⇒ no unit, reason kept.
        let estimated = try #require(displays.first { $0.name == "Estimated bitrate" })
        #expect(estimated.value == nil)
        #expect(estimated.unit == nil)
        #expect(estimated.detail == "cannot estimate")
    }

    @Test func uncertainNumericWithValueKeepsItsUnit() throws {
        var properties = TechnicalProperties()
        properties.estimatedBitrate = .uncertain(value: 180_904, reason: "estimated")
        let displays = ReportPropertyFormatter.displays(for: properties)

        let estimated = try #require(displays.first { $0.name == "Estimated bitrate" })
        #expect(estimated.value == "180904")
        #expect(estimated.unit == "bitsPerSecond")
    }
}
