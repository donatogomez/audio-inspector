import Testing

import AudioInspectorDomain

/// The model's own rules, over constructed values — **no file, no DSP, no framework**. Everything here
/// is about what the type can and cannot represent; whether the numbers are *correct* for a given
/// signal is the accumulator's question and is not asked in this file.
@Suite("Domain — true peak measurement")
struct TruePeakMeasurementTests {
    private let method = TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1)!

    private func channel(_ sampleCount: Int, _ truePeak: Float?) throws -> TruePeakMeasurement.Channel {
        try #require(TruePeakMeasurement.Channel(sampleCount: sampleCount, truePeak: truePeak))
    }

    private func measurement(_ channels: [TruePeakMeasurement.Channel]) throws -> TruePeakMeasurement {
        try #require(TruePeakMeasurement(channels: channels, method: method))
    }

    // MARK: - Channel counts

    @Test("a mono measurement reports one channel and takes its value as the overall")
    func mono() throws {
        let measured = try measurement([channel(44_100, 0.9)])
        #expect(measured.channels.count == 1)
        #expect(measured.channels[0].truePeak == 0.9)
        #expect(measured.overallTruePeak == 0.9)
    }

    @Test("a stereo measurement keeps each channel's own value, in order")
    func stereo() throws {
        let measured = try measurement([channel(44_100, 0.9), channel(44_100, 0.3)])
        #expect(measured.channels.map(\.truePeak) == [0.9, 0.3])
        #expect(measured.overallTruePeak == 0.9)
    }

    @Test("a multichannel measurement takes the maximum across every channel")
    func multichannel() throws {
        let measured = try measurement([
            channel(1_000, 0.1), channel(1_000, 0.55), channel(1_000, 0.2),
            channel(1_000, 0.44), channel(1_000, 0.3), channel(1_000, 0.05),
        ])
        #expect(measured.channels.count == 6)
        #expect(measured.overallTruePeak == 0.55)
    }

    @Test("the channel index is positional, and the type asserts no layout")
    func positionalChannels() throws {
        let measured = try measurement([channel(10, 0.2), channel(10, 0.8)])
        // The only way to identify a channel is its position — there is nothing named left or right to
        // read, which is what keeps a stereo pair from being asserted for a file that never declared one.
        #expect(measured.channels.first?.truePeak == 0.2)
        #expect(measured.channels.last?.truePeak == 0.8)
    }

    // MARK: - Zero frames versus a measured zero

    @Test("a channel with no frames reports no value, not a zero")
    func emptyChannelIsNotComputable() throws {
        let empty = try channel(0, nil)
        #expect(empty.sampleCount == 0)
        #expect(empty.truePeak == nil)
    }

    @Test("a channel that was measured and is silent reports a real zero")
    func silenceIsAMeasuredZero() throws {
        let silent = try channel(44_100, 0)
        #expect(silent.truePeak == 0)
        // The distinction the whole rule exists for: absent and zero are different answers.
        #expect(silent.truePeak != nil)
    }

    @Test("every channel empty leaves the overall with nothing to report")
    func allChannelsEmpty() throws {
        let measured = try measurement([channel(0, nil), channel(0, nil)])
        #expect(measured.overallTruePeak == nil)
    }

    @Test("an empty channel beside a measured one does not drag the overall down")
    func oneEmptyOneMeasured() throws {
        let measured = try measurement([channel(0, nil), channel(44_100, 0.75)])
        // An absence contributes nothing; it must not be read as a zero that a maximum would ignore
        // anyway, nor as a value that lowers the answer.
        #expect(measured.overallTruePeak == 0.75)
    }

    @Test("an empty channel beside a silent one keeps them distinguishable")
    func emptyBesideSilent() throws {
        let measured = try measurement([channel(0, nil), channel(1_000, 0)])
        #expect(measured.overallTruePeak == 0)
        #expect(measured.channels[0].truePeak == nil)
        #expect(measured.channels[1].truePeak == 0)
    }

    // MARK: - The value range: nothing normalised, nothing clamped

    @Test("values at and around full scale survive construction exactly", arguments: [
        Float(0), 0.5, 0.9999999, 1.0, 1.0000001, 1.05, 1.5, 8.0, 1_000.0,
    ] as [Float])
    func valuesSurviveUnchanged(_ value: Float) throws {
        let measured = try measurement([channel(1_000, value)])
        #expect(measured.channels[0].truePeak == value)
        #expect(measured.overallTruePeak == value)
    }

    @Test("a value beyond full scale is kept, never clamped to one")
    func beyondFullScaleIsNotClamped() throws {
        let measured = try measurement([channel(1_000, 1.5)])
        #expect(measured.overallTruePeak == 1.5)
        #expect(measured.overallTruePeak != 1.0)
    }

    @Test("nothing is normalised: two measurements of different level stay different")
    func nothingIsNormalised() throws {
        let quiet = try measurement([channel(1_000, 0.1)])
        let loud = try measurement([channel(1_000, 1.2)])
        #expect(quiet.overallTruePeak == 0.1)
        #expect(loud.overallTruePeak == 1.2)
        // A type that normalised would make these compare equal, which would destroy exactly the
        // comparison between two copies of the same music that this project exists for.
        #expect(quiet != loud)
    }

    @Test("the stored value is linear, never a decibel figure")
    func valuesAreLinear() throws {
        // 1.0 is full scale and would be 0 dBTP; 0.5 would be −6.02 dBTP. A model holding decibels
        // would have to represent full scale as 0, which is the value linear scale uses for silence.
        let fullScale = try measurement([channel(1_000, 1.0)])
        let silence = try measurement([channel(1_000, 0)])
        #expect(fullScale.overallTruePeak == 1.0)
        #expect(silence.overallTruePeak == 0)
        #expect(fullScale != silence)
    }

    // MARK: - Contradictory states are unrepresentable

    @Test("a channel with no frames cannot carry a value")
    func emptyChannelWithAValueIsRejected() {
        #expect(TruePeakMeasurement.Channel(sampleCount: 0, truePeak: 0) == nil)
        #expect(TruePeakMeasurement.Channel(sampleCount: 0, truePeak: 0.9) == nil)
    }

    @Test("a channel with frames cannot omit its value")
    func measuredChannelWithoutAValueIsRejected() {
        #expect(TruePeakMeasurement.Channel(sampleCount: 1, truePeak: nil) == nil)
        #expect(TruePeakMeasurement.Channel(sampleCount: 44_100, truePeak: nil) == nil)
    }

    @Test("a negative true peak is rejected — it is a maximum of absolute values")
    func negativeIsRejected() {
        #expect(TruePeakMeasurement.Channel(sampleCount: 10, truePeak: -0.0001) == nil)
        #expect(TruePeakMeasurement.Channel(sampleCount: 10, truePeak: -1) == nil)
    }

    @Test("a value that is not a number is rejected")
    func nanIsRejected() {
        #expect(TruePeakMeasurement.Channel(sampleCount: 10, truePeak: .nan) == nil)
        #expect(TruePeakMeasurement.Channel(sampleCount: 10, truePeak: .signalingNaN) == nil)
    }

    @Test("infinities are rejected")
    func infinitiesAreRejected() {
        #expect(TruePeakMeasurement.Channel(sampleCount: 10, truePeak: .infinity) == nil)
        #expect(TruePeakMeasurement.Channel(sampleCount: 10, truePeak: -.infinity) == nil)
    }

    @Test("a negative sample count is rejected")
    func negativeSampleCountIsRejected() {
        #expect(TruePeakMeasurement.Channel(sampleCount: -1, truePeak: 0.5) == nil)
        #expect(TruePeakMeasurement.Channel(sampleCount: -1, truePeak: nil) == nil)
    }

    @Test("a measurement of no channels at all is rejected")
    func emptyChannelListIsRejected() {
        #expect(TruePeakMeasurement(channels: [], method: method) == nil)
    }

    @Test("negative zero is accepted and behaves as zero")
    func negativeZeroIsAccepted() throws {
        // `-0.0 >= 0` is true in IEEE 754, so the guard admits it. It compares equal to zero, so it
        // cannot be mistaken for a negative value by any consumer.
        let measured = try measurement([channel(10, -0.0)])
        #expect(measured.overallTruePeak == 0)
    }

    // MARK: - The overall cannot diverge from the channels

    @Test("the overall is derived, so there is no way to construct one that disagrees")
    func overallIsDerived() throws {
        let measured = try measurement([channel(100, 0.2), channel(100, 0.9), channel(100, 0.4)])
        // The only source of the overall is the channels themselves: the type exposes no initialiser
        // argument and no stored property for it, so a producer cannot fill in a different number.
        #expect(measured.overallTruePeak == measured.channels.compactMap(\.truePeak).max())
        #expect(measured.overallTruePeak == 0.9)
    }

    @Test("the overall is the maximum, never a mean")
    func overallIsNotAMean() throws {
        let measured = try measurement([channel(100, 0.2), channel(100, 1.0)])
        #expect(measured.overallTruePeak == 1.0)
        // The mean would be 0.6 — a level neither channel reached.
        #expect(measured.overallTruePeak != 0.6)
    }

    @Test("the overall ignores channel order")
    func overallIgnoresOrder() throws {
        let ascending = try measurement([channel(100, 0.1), channel(100, 0.7)])
        let descending = try measurement([channel(100, 0.7), channel(100, 0.1)])
        #expect(ascending.overallTruePeak == descending.overallTruePeak)
    }

    // MARK: - The method descriptor

    @Test("the method records the factor and the filter that produced the value")
    func methodTravelsWithTheValue() throws {
        let measured = try measurement([channel(100, 0.9)])
        #expect(measured.method.oversamplingFactor == 8)
        #expect(measured.method.filter == .polyphaseFIRv1)
    }

    @Test("the filter identity is a stable written string, not a Swift symbol")
    func filterIdentityIsStable() {
        // Pinned deliberately: this exact text is what an export carries and what a later reader
        // compares against. A refactor that renames the static member must not change it, and this
        // assertion is what makes that a test failure rather than a silent contract break.
        #expect(TruePeakFilterIdentifier.polyphaseFIRv1.rawValue == "polyphase_fir_v1")
    }

    @Test("the identity carries a version, so a different methodology cannot reuse it")
    func filterIdentityIsVersioned() {
        #expect(TruePeakFilterIdentifier.polyphaseFIRv1.rawValue.hasSuffix("_v1"))
        let other = TruePeakFilterIdentifier(rawValue: "polyphase_fir_v2")
        #expect(other != .polyphaseFIRv1)
    }

    @Test("a factor that is not a positive multiplier is rejected", arguments: [0, -1, -8])
    func nonPositiveFactorIsRejected(_ factor: Int) {
        #expect(TruePeakMethod(oversamplingFactor: factor, filter: .polyphaseFIRv1) == nil)
    }

    @Test("the model does not police the methodological floor, only arithmetic sense")
    func factorFloorIsNotTheModelsJob() {
        // ADR-0006's "≥ 4×" is a methodology rule owned by whoever chooses the constant. The model
        // refuses only what is arithmetically impossible, so this stays representable on purpose.
        #expect(TruePeakMethod(oversamplingFactor: 1, filter: .polyphaseFIRv1) != nil)
    }

    @Test("two measurements differing only in method are not equal")
    func methodParticipatesInEquality() throws {
        let eightTimesMethod = try #require(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1))
        let fourTimesMethod = try #require(TruePeakMethod(oversamplingFactor: 4, filter: .polyphaseFIRv1))
        let measured = try [channel(100, 0.9)]
        let eightTimes = try #require(TruePeakMeasurement(channels: measured, method: eightTimesMethod))
        let fourTimes = try #require(TruePeakMeasurement(channels: measured, method: fourTimesMethod))
        // The same number produced two ways is not the same measurement — which is the whole reason
        // the methodology travels with the value.
        #expect(eightTimes != fourTimes)
    }

    // MARK: - Conformances

    @Test("equality reproduces the linear values exactly")
    func equalityIsByValue() throws {
        let left = try measurement([channel(100, 1.0500001), channel(0, nil)])
        let right = try measurement([channel(100, 1.0500001), channel(0, nil)])
        #expect(left == right)

        let nudged = try measurement([channel(100, 1.0500002), channel(0, nil)])
        #expect(left != nudged)
    }

    @Test("a differing sample count makes two channels unequal even at the same level")
    func sampleCountParticipatesInEquality() throws {
        #expect(try channel(100, 0.5) != (try channel(200, 0.5)))
    }

    @Test("the model is not Codable — the wire form belongs to the export mapper")
    func isNotCodable() {
        // Checked at runtime rather than by a comment: conforming this type to `Encodable` would
        // advertise a `schemaVersion` contract that lives in another module entirely (ADR-0009), and a
        // future contributor adding the conformance for convenience would break that silently.
        #expect(!(TruePeakMeasurement.self is any Encodable.Type))
        #expect(!(TruePeakMeasurement.self is any Decodable.Type))
        #expect(!(TruePeakMeasurement.Channel.self is any Encodable.Type))
        #expect(!(TruePeakMethod.self is any Encodable.Type))
        #expect(!(TruePeakFilterIdentifier.self is any Encodable.Type))
    }

    @Test("the model is not Comparable and not Hashable — neither has a meaning here")
    func carriesNoUnearnedConformances() {
        // There is no semantic order over measurements: "louder" is a question about one value, not
        // about two whole measurements with their own methods. And nothing keys a dictionary by one.
        #expect(!(TruePeakMeasurement.self is any Comparable.Type))
        #expect(!(TruePeakMeasurement.Channel.self is any Comparable.Type))
        #expect(!(TruePeakMeasurement.self is any Hashable.Type))
        #expect(!(TruePeakMethod.self is any Hashable.Type))
    }

    @Test("the model is Sendable")
    func isSendable() throws {
        // Compile-time evidence: a non-`Sendable` type cannot satisfy this generic constraint under
        // Swift 6, so this failing to build *is* the assertion.
        func requireSendable(_ value: some Sendable) -> Bool { _ = value; return true }
        #expect(requireSendable(try measurement([channel(10, 0.5)])))
        #expect(requireSendable(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1)!))
        #expect(requireSendable(TruePeakFilterIdentifier.polyphaseFIRv1))
    }
}
