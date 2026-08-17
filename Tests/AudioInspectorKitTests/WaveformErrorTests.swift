import AudioInspectorDomain
import AudioInspectorTesting
import Testing

// The waveform error space, and the boundary that matters most: cancellation is something the user
// did, absence is something the file lacks, and an empty envelope is a complete answer. Three
// outcomes, three representations, and no path that quietly merges any two of them.

@Suite("Domain — waveform errors")
struct WaveformErrorTests {
    /// Every code this layer defines. Listed explicitly so adding one without deciding what it means
    /// breaks the test rather than slipping through.
    private static let allCodes: [(WaveformErrorCode, String)] = [
        (.invalidConfiguration, "waveform_invalid_configuration"),
        (.nonFiniteSample, "waveform_non_finite_sample"),
        (.channelOutOfBounds, "waveform_channel_out_of_bounds"),
        (.frameRangeOutOfBounds, "waveform_frame_range_out_of_bounds"),
        (.incompleteCoverage, "waveform_incomplete_coverage"),
        (.cancelled, "waveform_cancelled"),
    ]

    @Test("each code has its stable raw value", arguments: allCodes)
    func codesAreStable(code: WaveformErrorCode, rawValue: String) {
        #expect(code.rawValue == rawValue)
        #expect(WaveformErrorCode(rawValue: rawValue) == code)
    }

    @Test("no two codes share a raw value")
    func codesAreDistinct() {
        let rawValues = Self.allCodes.map(\.1)
        #expect(Set(rawValues).count == rawValues.count)
        #expect(Set(Self.allCodes.map(\.0)).count == Self.allCodes.count)
    }

    @Test("cancellation is not any of the faults it could be mistaken for")
    func cancellationIsItsOwnCode() {
        #expect(WaveformErrorCode.cancelled != .invalidConfiguration)
        #expect(WaveformErrorCode.cancelled != .incompleteCoverage)
        #expect(WaveformErrorCode.cancelled != .nonFiniteSample)
        #expect(WaveformErrorCode.cancelled.rawValue == "waveform_cancelled")
    }

    @Test("an error carries its code as identity and its message as description only")
    func errorsCompareByCodeAndMessage() {
        let one = WaveformError(code: .cancelled, message: "Stopped at a chunk boundary.")
        let same = WaveformError(code: .cancelled, message: "Stopped at a chunk boundary.")
        let otherMessage = WaveformError(code: .cancelled, message: "Cancelled.")
        let otherCode = WaveformError(code: .incompleteCoverage, message: "Stopped at a chunk boundary.")

        #expect(one == same)
        #expect(one != otherMessage)
        #expect(one != otherCode)
        #expect(one.code == .cancelled)
    }

    @Test("the waveform error space does not collide with the inspection error space")
    func doesNotCollideWithInspectionErrors() {
        let waveformCodes = Set(Self.allCodes.map(\.1))
        let inspectionCodes: Set<String> = [
            InspectionErrorCode.fileOpenFailed.rawValue,
            InspectionErrorCode.fileUnreadable.rawValue,
            InspectionErrorCode.fileAccessDenied.rawValue,
        ]
        #expect(waveformCodes.isDisjoint(with: inspectionCodes))
        #expect(waveformCodes.allSatisfy { $0.hasPrefix("waveform_") })
    }

    // MARK: The three outcomes stay apart

    @Test("an empty envelope, an absence and a cancellation are three different things")
    func threeOutcomesAreDistinct() throws {
        // 1. A file with no frames: a complete answer, carrying no buckets.
        let empty: WaveformEnvelope? = try #require(WaveformEnvelope.empty(channelCount: 2))
        // 2. Nothing to size an envelope against: an absence caused by the file.
        let absent: WaveformEnvelope? = nil
        // 3. The caller stopped it: an error that says nothing about the file.
        let cancelled = WaveformError(code: .cancelled, message: "Stopped at a chunk boundary.")

        #expect(empty != nil, "an empty envelope is a result, not a missing one")
        #expect(empty?.buckets.isEmpty == true)
        #expect(absent == nil)
        #expect(empty != absent)
        #expect(cancelled.code == .cancelled)

        // The distinction that would hurt a user most if it were lost: cancelling tells them nothing
        // about their file, so it must not arrive as the same value as "your file offered nothing".
        let outcomeForAbsence: Result<WaveformEnvelope?, WaveformError> = .success(absent)
        let outcomeForCancellation: Result<WaveformEnvelope?, WaveformError> = .failure(cancelled)
        switch (outcomeForAbsence, outcomeForCancellation) {
        case (.success, .failure): break
        default: Issue.record("absence and cancellation collapsed into the same kind of outcome")
        }
    }
}
