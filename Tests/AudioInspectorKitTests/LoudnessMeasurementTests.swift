import Foundation
import Testing

import AudioInspectorDomain

// What the loudness value type will and will not represent.
//
// **No DSP here.** Nothing in this suite measures anything: it fixes what a *result* may be, which is a
// different contract from how one is produced. The algorithm lives in
// "Analysis — integrated loudness (48 kHz)".

@Suite("Domain — integrated loudness measurement")
struct LoudnessMeasurementTests {

    private let method = LoudnessMethod(algorithm: .integratedBS1770v1, weighting: .publishedAt48kHz)

    private func measurement(_ value: Double) -> LoudnessMeasurement? {
        LoudnessMeasurement(integratedLoudness: value, method: method)
    }

    // MARK: - Values a measurement may carry

    /// Every finite value is representable, including the ones a reader might not expect. The EBU target
    /// appears here as an ordinary number and nothing else: this type has no opinion about it.
    @Test(
        "any finite value is accepted, whatever its sign",
        arguments: [-70.5, -23.0, -18.0, -3.01, -0.0001, 0.0, 0.0001, 3.52, 12.0, 1e6, -1e6]
    )
    func acceptsEveryFiniteValue(_ value: Double) throws {
        let made = try #require(measurement(value))
        #expect(made.integratedLoudness == value)
    }

    /// A programme above full scale legitimately reads above zero, and nothing here may pull it back.
    @Test("a positive value is stored as it was measured, never limited to zero")
    func doesNotClampPositiveValues() throws {
        let made = try #require(measurement(3.5218))
        #expect(made.integratedLoudness == 3.5218)
        #expect(made.integratedLoudness > 0)
    }

    /// The absolute gate is a threshold on *blocks*. It is not a floor on the result, and this type does
    /// not impose one — a value below it is stored as given rather than refused or raised.
    @Test("the gate's own level is not a floor on the result")
    func doesNotFloorAtTheGate() throws {
        let made = try #require(measurement(-83.25))
        #expect(made.integratedLoudness == -83.25)
    }

    /// Full precision survives. A one-decimal presentation is the interface's business, exactly as
    /// `TechnicalProperties` stores hertz rather than "44.1 kHz".
    @Test("the value is stored at full precision, never rounded for display")
    func doesNotRound() throws {
        let made = try #require(measurement(-23.013869182152510))
        #expect(made.integratedLoudness == -23.013869182152510)
        #expect(made.integratedLoudness != -23.0)
    }

    // MARK: - Values that could not describe a measurement

    @Test("a non-finite value is refused rather than stored")
    func refusesNonFiniteValues() {
        #expect(measurement(.nan) == nil)
        #expect(measurement(.signalingNaN) == nil)
        #expect(measurement(.infinity) == nil)
        #expect(measurement(-.infinity) == nil)
    }

    /// −∞ is the loudness of a silent block, and it is exactly the value a producer must not be able to
    /// hand over: an undefined measurement is an absence, not a number at the bottom of the scale.
    @Test("negative infinity — a silent block's own loudness — cannot become a result")
    func silentBlockLoudnessIsNotStorable() {
        let silentBlockLoudness = -0.691 + 10 * log10(0.0)
        #expect(silentBlockLoudness == -.infinity)
        #expect(measurement(silentBlockLoudness) == nil)
    }

    // MARK: - Equality

    @Test("two measurements of the same value under the same method are equal")
    func equalityHoldsForIdenticalMeasurements() throws {
        #expect(try #require(measurement(-23.0)) == (try #require(measurement(-23.0))))
    }

    @Test("a differing value makes two measurements unequal")
    func valueParticipatesInEquality() throws {
        #expect(try #require(measurement(-23.0)) != (try #require(measurement(-23.1))))
    }

    /// The whole reason the method travels with the value: two files carrying the same number under
    /// different methodologies are not the same measurement, and a consumer must be able to tell.
    @Test("the same value under a different method is a different measurement")
    func methodParticipatesInEquality() throws {
        let other = LoudnessMethod(
            algorithm: LoudnessAlgorithmIdentifier(rawValue: "itu_r_bs1770_5_integrated_v2"),
            weighting: .publishedAt48kHz
        )
        let published = try #require(measurement(-23.0))
        let underOther = try #require(
            LoudnessMeasurement(integratedLoudness: -23.0, method: other)
        )
        #expect(published != underOther)
    }

    /// And the weighting alone is enough to make them different, which is what will separate a value
    /// produced from the published 48 kHz coefficients from one produced by a later derivation.
    @Test("a different weighting provenance alone makes two measurements unequal")
    func weightingParticipatesInEquality() throws {
        let derived = LoudnessMethod(
            algorithm: .integratedBS1770v1,
            weighting: LoudnessWeightingIdentifier(rawValue: "prototype_rediscretised_v1")
        )
        let published = try #require(measurement(-23.0))
        let underDerived = try #require(
            LoudnessMeasurement(integratedLoudness: -23.0, method: derived)
        )
        #expect(published != underDerived)
        #expect(published.integratedLoudness == underDerived.integratedLoudness)
    }

    // MARK: - The recorded identities

    /// The `rawValue` **is** the identity, so it survives renaming the static member, moving the file or
    /// restructuring the accumulator. Pinned here for that reason: changing it is changing what every
    /// previously reported figure claimed about itself.
    @Test("the method identities are the exact strings that were published with results")
    func identitiesAreStable() {
        #expect(LoudnessAlgorithmIdentifier.integratedBS1770v1.rawValue == "itu_r_bs1770_5_integrated_v1")
        #expect(LoudnessWeightingIdentifier.publishedAt48kHz.rawValue == "itu_r_bs1770_5_tables_1_2_48k")
    }

    /// The revision lives inside the algorithm's identity rather than beside it, so a state naming one
    /// revision's rules next to a different revision is not representable.
    @Test("the algorithm identity names the revision it implements")
    func identityCarriesTheRevision() {
        #expect(LoudnessAlgorithmIdentifier.integratedBS1770v1.rawValue.contains("bs1770_5"))
        #expect(LoudnessAlgorithmIdentifier.integratedBS1770v1.rawValue.contains("integrated"))
    }

    /// Nothing in the model claims conformance, certification or a target. Asserted rather than left to
    /// review, because a field added for convenience would turn a measurement into a verdict.
    @Test("no identity claims conformance, certification or a delivery target")
    func nothingClaimsCompliance() {
        let vocabulary = [
            "compliant", "compliance", "certified", "certification", "conformant", "conformance",
            "ebu_mode", "pass", "valid", "target",
        ]
        for raw in [
            LoudnessAlgorithmIdentifier.integratedBS1770v1.rawValue,
            LoudnessWeightingIdentifier.publishedAt48kHz.rawValue,
        ] {
            for word in vocabulary {
                #expect(!raw.contains(word), "\(raw) must not contain \(word)")
            }
        }
    }

    // MARK: - Conformances, present and absent

    @Test("the model is Sendable")
    func isSendable() throws {
        // Compile-time evidence: a non-`Sendable` type cannot satisfy this generic constraint under
        // Swift 6, so this failing to build *is* the assertion.
        func requireSendable(_ value: some Sendable) -> Bool { _ = value; return true }
        #expect(requireSendable(try #require(measurement(-23.0))))
        #expect(requireSendable(method))
        #expect(requireSendable(LoudnessAlgorithmIdentifier.integratedBS1770v1))
        #expect(requireSendable(LoudnessWeightingIdentifier.publishedAt48kHz))
    }

    @Test("the model is not Codable — the wire form belongs to the export mapper")
    func isNotCodable() {
        // Checked at runtime rather than by a comment: conforming this type would advertise a
        // `schemaVersion` contract that lives in another module entirely (ADR-0009), and a future
        // contributor adding it for convenience would break that silently.
        #expect(!(LoudnessMeasurement.self is any Encodable.Type))
        #expect(!(LoudnessMeasurement.self is any Decodable.Type))
        #expect(!(LoudnessMethod.self is any Encodable.Type))
        #expect(!(LoudnessAlgorithmIdentifier.self is any Encodable.Type))
        #expect(!(LoudnessWeightingIdentifier.self is any Encodable.Type))
    }

    @Test("the model is not Comparable and not Hashable — neither has a meaning here")
    func carriesNoUnearnedConformances() {
        // There is no order over measurements: "louder" is a question about one value, not about two
        // whole measurements with their own methods — and comparing across methods would be comparing
        // numbers produced by different rules. Nothing keys a dictionary by one either.
        #expect(!(LoudnessMeasurement.self is any Comparable.Type))
        #expect(!(LoudnessMeasurement.self is any Hashable.Type))
        #expect(!(LoudnessMethod.self is any Comparable.Type))
        #expect(!(LoudnessMethod.self is any Hashable.Type))
    }
}
