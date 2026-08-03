import AVFoundation
import CoreMedia
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import AudioInspectorMedia
import AudioInspectorDomain

/// Task 3.7 — **pure mapper** unit tests for `AVFoundationAudioFilePropertyReader`.
///
/// Every case here drives one field mapper with **controlled in-memory inputs** (a hand-built
/// `AudioStreamBasicDescription`, a `CMTime`, a `Float` data-rate, a `UTType`, or a `LoadedProperty`
/// state) — **no real files, no AVFoundation asset loading**. The mappers are reachable because the
/// adapter's pure helper surface is `internal` (the 3.7 testability seam); they are exercised on a
/// default reader instance (the field mappers use no instance state). Assertions key on the stable
/// `Property` case / carried value / property-failure `code` — never on descriptive message text.
@Suite("Media — AVFoundation property mapping (pure, in-memory)")
struct AVFoundationPropertyMappingTests {

    /// A default reader; its field mappers ignore instance state, so this is a pure calculator here.
    private let reader = AVFoundationAudioFilePropertyReader()

    // MARK: - Builders & assertion helpers

    /// A controlled ASBD — the only input the stream-derived mappers read.
    private func makeASBD(
        formatID: AudioFormatID = kAudioFormatLinearPCM,
        sampleRate: Double = 44_100,
        channels: UInt32 = 2,
        bitsPerChannel: UInt32 = 16
    ) -> AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mFormatID = formatID
        asbd.mSampleRate = sampleRate
        asbd.mChannelsPerFrame = channels
        asbd.mBitsPerChannel = bitsPerChannel
        return asbd
    }

    private func expectFailed<Value>(_ property: Property<Value>) {
        guard case let .failed(failure) = property else {
            Issue.record("expected .failed, got \(property)"); return
        }
        // Identity is the stable code, not the (descriptive, non-asserted) message.
        #expect(failure.code == .propertyReadError)
    }

    private func expectUncertain<Value: Equatable>(_ property: Property<Value>, value: Value?) {
        guard case let .uncertain(carried, _) = property else {
            Issue.record("expected .uncertain, got \(property)"); return
        }
        #expect(carried == value)
    }

    // MARK: - sampleRate (ASBD mSampleRate → Property<Int>)

    @Test(arguments: [
        (44_100.0, Property<Int>.available(44_100)),
        (22_050.0, .available(22_050)),
        (0.0, .unavailable(reason: nil)),          // zero
        (-1.0, .unavailable(reason: nil)),         // negative
        (44_100.5, .unavailable(reason: nil)),     // fractional → not an exact Int
        (Double.nan, .unavailable(reason: nil)),   // NaN
        (Double.infinity, .unavailable(reason: nil)), // infinite
    ])
    func sampleRateFromASBD(hertz: Double, expected: Property<Int>) {
        #expect(reader.sampleRate(from: .value(makeASBD(sampleRate: hertz))) == expected)
    }

    // MARK: - channelCount (ASBD mChannelsPerFrame → Property<Int>)

    @Test(arguments: [
        (UInt32(2), Property<Int>.available(2)),
        (UInt32(1), .available(1)),
        (UInt32(0), .unavailable(reason: nil)), // zero channels
    ])
    func channelCountFromASBD(channels: UInt32, expected: Property<Int>) {
        #expect(reader.channelCount(from: .value(makeASBD(channels: channels))) == expected)
    }

    // MARK: - bitDepth (ASBD mBitsPerChannel, PCM-only → Property<Int>)

    @Test(arguments: [
        (kAudioFormatLinearPCM, UInt32(16), Property<Int>.available(16)), // PCM 16
        (kAudioFormatLinearPCM, UInt32(24), .available(24)),              // PCM 24
        (kAudioFormatLinearPCM, UInt32(0), .unavailable(reason: nil)),    // PCM with zero field
        (kAudioFormatMPEG4AAC, UInt32(16), .unavailable(reason: nil)),    // non-PCM → conservative
    ])
    func bitDepthFromASBD(formatID: AudioFormatID, bits: UInt32, expected: Property<Int>) {
        let asbd = makeASBD(formatID: formatID, bitsPerChannel: bits)
        #expect(reader.bitDepth(from: .value(asbd)) == expected)
    }

    // MARK: - codec (ASBD mFormatID → Property<String> token)

    @Test func codecFromLpcmIsAvailableToken() {
        #expect(reader.codec(from: .value(makeASBD(formatID: kAudioFormatLinearPCM))) == .available("lpcm"))
    }

    @Test func codecFromAacTrimsPaddingToAvailableToken() {
        // kAudioFormatMPEG4AAC == 'aac ' (trailing space) → padding trimmed to "aac".
        #expect(reader.codec(from: .value(makeASBD(formatID: kAudioFormatMPEG4AAC))) == .available("aac"))
    }

    @Test func codecFromZeroFormatIDIsUnavailable() {
        #expect(reader.codec(from: .value(makeASBD(formatID: 0))) == .unavailable(reason: nil))
    }

    // MARK: - fourCharCodeToken (stable, non-localized FourCC serialization)

    @Test(arguments: [
        (UInt32(0x6C70_636D), "lpcm"),        // 'lpcm'
        (UInt32(0x616C_6163), "alac"),        // 'alac'
        (UInt32(0x6161_6320), "aac"),         // 'aac ' → trailing space trimmed
        (UInt32(0x2E6D_7033), ".mp3"),        // '.mp3' → printable, kept verbatim
        (UInt32(0x6D73_0000), "0x6D730000"),  // NUL bytes → hex fallback
        (UInt32(0x6162_0163), "0x61620163"),  // control byte (0x01) → hex fallback
        (UInt32(0x6120_6263), "0x61206263"),  // internal space → hex fallback
        (UInt32(0x2061_6263), "0x20616263"),  // leading space → hex fallback
        (UInt32(0x0000_0000), "0x00000000"),  // all NUL → hex fallback
        (UInt32(0x2020_2020), "0x20202020"),  // all spaces → empty after trim → hex fallback
    ])
    func fourCharCodeToken(code: UInt32, expected: String) {
        #expect(AVFoundationAudioFilePropertyReader.fourCharCodeToken(code) == expected)
    }

    // MARK: - duration (CMTime → Property<Double>)

    @Test func durationPositiveIsAvailable() {
        let time = CMTime(seconds: 2.0, preferredTimescale: 44_100)
        #expect(reader.duration(from: .value(time)) == .available(2.0))
    }

    @Test func durationZeroIsUncertainKeepingZero() {
        expectUncertain(reader.duration(from: .value(.zero)), value: 0)
    }

    @Test func durationNegativeIsUnavailable() {
        let time = CMTime(seconds: -1.0, preferredTimescale: 1)
        #expect(reader.duration(from: .value(time)) == .unavailable(reason: nil))
    }

    @Test func durationInvalidIsUnavailable() {
        #expect(reader.duration(from: .value(.invalid)) == .unavailable(reason: nil))
    }

    @Test func durationIndefiniteIsUnavailable() {
        #expect(reader.duration(from: .value(.indefinite)) == .unavailable(reason: nil))
    }

    @Test func durationInfiniteIsUnavailable() {
        #expect(reader.duration(from: .value(.positiveInfinity)) == .unavailable(reason: nil))
    }

    @Test func durationAbsenceIsUnavailable() {
        #expect(reader.duration(from: .unavailable) == .unavailable(reason: nil))
    }

    @Test func durationReadErrorIsFailed() {
        expectFailed(reader.duration(from: .failed))
    }

    // MARK: - estimatedBitrate (Float estimatedDataRate → always uncertain, except read error)

    @Test(arguments: [
        (Float(320_000), Optional(320_000)),   // positive integral → carried as tentative value
        (Float(128_000.5), nil),               // positive fractional → no exact Int → no value
        (Float(0), nil),                        // zero → absence, no value
        (Float(-1), nil),                       // negative → no value
        (Float.nan, nil),                       // NaN → no value
        (Float.infinity, nil),                  // infinite → no value
    ])
    func estimatedBitrateFromValue(rate: Float, expected: Int?) {
        expectUncertain(reader.estimatedBitrate(from: .value(rate)), value: expected)
    }

    @Test func estimatedBitrateAbsenceIsUncertainWithoutValue() {
        expectUncertain(reader.estimatedBitrate(from: .unavailable), value: nil)
    }

    @Test func estimatedBitrateReadErrorIsFailed() {
        expectFailed(reader.estimatedBitrate(from: .failed))
    }

    // MARK: - container (pure UTType? → Property<String>; IO error path via a missing URL)

    @Test func containerFromResolvedTypeIsUncertainWithIdentifier() {
        let property = AVFoundationAudioFilePropertyReader.container(fromContentType: .wav)
        expectUncertain(property, value: UTType.wav.identifier)
    }

    @Test func containerFromNoTypeIsUnavailable() {
        #expect(AVFoundationAudioFilePropertyReader.container(fromContentType: nil) == .unavailable(reason: nil))
    }

    @Test func containerReadErrorIsFailed() {
        // A resource-values read against a missing path errors → `failed` (distinct from absence).
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).wav")
        expectFailed(reader.container(from: missing))
    }

    // MARK: - Stream propagation & per-property failure scope (task 3.6/3.7)

    @Test func absentFormatDescriptionMakesStreamFieldsUnavailable() {
        let stream = AVFoundationAudioFilePropertyReader.streamProperty(from: .unavailable)
        #expect(reader.sampleRate(from: stream) == .unavailable(reason: nil))
        #expect(reader.channelCount(from: stream) == .unavailable(reason: nil))
        #expect(reader.bitDepth(from: stream) == .unavailable(reason: nil))
        #expect(reader.codec(from: stream) == .unavailable(reason: nil))
    }

    @Test func formatDescriptionReadErrorFailsEveryStreamFieldOnly() {
        // A format-descriptions read error → all four ASBD fields `failed` (not a global throw)...
        let stream = AVFoundationAudioFilePropertyReader.streamProperty(from: .failed)
        expectFailed(reader.sampleRate(from: stream))
        expectFailed(reader.channelCount(from: stream))
        expectFailed(reader.bitDepth(from: stream))
        expectFailed(reader.codec(from: stream))
        // ...while independent fields, fed their own good inputs, still map cleanly.
        #expect(reader.duration(from: .value(CMTime(seconds: 1.0, preferredTimescale: 1))) == .available(1.0))
        expectUncertain(reader.estimatedBitrate(from: .value(256_000)), value: 256_000)
    }
}
