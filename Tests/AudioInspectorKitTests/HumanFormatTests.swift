import Foundation
import Testing

@testable import FeatureAnalysis

/// The presentation formatter, asserted directly. Every expectation here is a literal string, which is
/// only safe because the formatter pins its locale: otherwise these would pass on one machine and fail
/// on another.
@Suite("Feature — human formatting")
struct HumanFormatTests {

    @Test func theFormatterDoesNotDependOnTheMachineLocale() {
        // The pinned locale is the whole reason the literals below are stable.
        #expect(HumanFormat.locale.identifier == "en_US")
    }

    // MARK: - Sizes

    @Test func byteCountsAreReadableAndKeepTheExactFigure() {
        #expect(HumanFormat.byteCount(8_421_376) == "8.4 MB")
        #expect(HumanFormat.byteCountExact(8_421_376) == "8,421,376 bytes")
        #expect(HumanFormat.byteCount(0) == "Zero kB")
        #expect(HumanFormat.byteCountExact(0) == "0 bytes")
    }

    // MARK: - Time

    @Test(arguments: [
        (10.5, "0:10"),
        (372.51, "6:13"), // rounds to the nearest second; the exact value is kept as detail
        (59.0, "0:59"),
        (3_600.0, "1:00:00"),
        (3_723.0, "1:02:03"),
    ])
    func durationsReadAsClockTime(seconds: Double, expected: String) {
        #expect(HumanFormat.duration(seconds) == expected)
    }

    /// A duration that is not a real quantity yields nothing rather than a fabricated one.
    @Test func nonFiniteOrNegativeDurationsProduceNoValue() {
        #expect(HumanFormat.duration(.nan) == nil)
        #expect(HumanFormat.duration(.infinity) == nil)
        #expect(HumanFormat.duration(-1) == nil)
    }

    @Test func exactDurationsKeepTheirFraction() {
        #expect(HumanFormat.durationExact(372.51) == "372.51 seconds")
        #expect(HumanFormat.durationExact(10) == "10 seconds")
    }

    // MARK: - Rates

    @Test(arguments: [
        (44_100, "44.1 kHz", "44,100 Hz"),
        (48_000, "48 kHz", "48,000 Hz"),
        (96_000, "96 kHz", "96,000 Hz"),
        (22_050, "22.05 kHz", "22,050 Hz"),
    ])
    func sampleRatesAreScaledAndPreserved(hertz: Int, readable: String, exact: String) {
        #expect(HumanFormat.sampleRate(hertz) == readable)
        #expect(HumanFormat.sampleRateExact(hertz) == exact)
    }

    @Test(arguments: [
        (128_000, "128 kbps", "128,000 bit/s"),
        (1_411_200, "1,411.2 kbps", "1,411,200 bit/s"),
        (320_000, "320 kbps", "320,000 bit/s"),
    ])
    func bitratesStayInKilobitsAtEveryScale(bps: Int, readable: String, exact: String) {
        #expect(HumanFormat.bitrate(bps) == readable)
        #expect(HumanFormat.bitrateExact(bps) == exact)
    }

    // MARK: - Audio shape

    /// Only one and two are named. Above that the domain knows a count, not a layout, so calling six
    /// channels "5.1" would assert a configuration that was never read.
    @Test(arguments: [
        (1, "Mono"),
        (2, "Stereo"),
        (3, "3 channels"),
        (6, "6 channels"),
        (8, "8 channels"),
    ])
    func channelCountsAreNamedOnlyWhereCertain(count: Int, expected: String) {
        #expect(HumanFormat.channels(count) == expected)
    }

    @Test func noChannelCountIsEverDescribedAsASurroundLayout() {
        for count in 1 ... 16 {
            let named = HumanFormat.channels(count)
            #expect(!named.contains("5.1"))
            #expect(!named.contains("7.1"))
            #expect(!named.lowercased().contains("surround"))
        }
    }

    @Test func exactChannelCountsAgreeInNumber() {
        #expect(HumanFormat.channelsExact(1) == "1 channel")
        #expect(HumanFormat.channelsExact(2) == "2 channels")
        #expect(HumanFormat.channelsExact(6) == "6 channels")
    }

    @Test func bitDepthReadsAsABitWidth() {
        #expect(HumanFormat.bitDepth(16) == "16-bit")
        #expect(HumanFormat.bitDepth(24) == "24-bit")
    }

    // MARK: - Dates

    @Test func datesAreFormattedAtAFixedWidth() {
        let date = Date(timeIntervalSince1970: 1_749_718_980)
        let formatted = HumanFormat.dateTime(date)
        // Pinned locale ⇒ a stable, non-empty rendering that is not the raw description.
        #expect(!formatted.isEmpty)
        #expect(formatted != String(describing: date))
        #expect(formatted.contains("2025"))
    }

    // MARK: - Nothing here judges

    /// The formatter produces names and magnitudes. If a judgement ever creeps into one of these
    /// strings, this catches it (invariant #4: format is not quality).
    @Test func noFormattedValueCharacterisesQuality() {
        let samples = [
            HumanFormat.byteCount(8_421_376), HumanFormat.byteCountExact(8_421_376),
            HumanFormat.duration(372.51) ?? "", HumanFormat.durationExact(372.51),
            HumanFormat.sampleRate(44_100), HumanFormat.sampleRateExact(44_100),
            HumanFormat.bitrate(128_000), HumanFormat.bitrateExact(128_000),
            HumanFormat.channels(2), HumanFormat.channelsExact(2), HumanFormat.bitDepth(16),
        ]
        let forbidden = ["good", "bad", "better", "worse", "high", "low", "quality", "professional", "recommended"]
        for sample in samples {
            for word in forbidden {
                #expect(!sample.lowercased().contains(word))
            }
        }
    }
}
