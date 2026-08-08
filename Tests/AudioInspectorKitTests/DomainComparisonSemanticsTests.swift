import Testing

@testable import AudioInspectorDomain

// The comparison semantics of group 2, asserted over the types themselves. Pure value types only — no
// files, no reports, no JSON, no framework. `FileComparison` does not exist yet and is not referenced.

/// Every `PropertyState`, so a matrix can enumerate all 25 pairs rather than a chosen few.
private let allStates: [PropertyState] = [.available, .unavailable, .unsupported, .uncertain, .failed]

/// A `Property` in each state, carrying `value` wherever the case can hold one.
private func property<Value>(_ state: PropertyState, value: Value) -> Property<Value> {
    switch state {
    case .available: .available(value)
    case .unavailable: .unavailable(reason: nil)
    case .unsupported: .unsupported(reason: "the format cannot express it")
    case .uncertain: .uncertain(value: value, reason: "estimated")
    case .failed: .failed(PropertyFailure(code: .propertyReadError, message: "boom"))
    }
}

@Suite("Domain — comparison state")
struct PropertyStateTests {

    /// The mapping is total, and each case lands on its own state. A `Property` case gained later
    /// breaks compilation here rather than being silently classified.
    @Test("every property case maps to its own state")
    func mappingIsTotalAndDistinct() {
        #expect(PropertyState(of: Property.available(1)) == .available)
        #expect(PropertyState(of: Property<Int>.unavailable(reason: nil)) == .unavailable)
        #expect(PropertyState(of: Property<Int>.unavailable(reason: "not carried")) == .unavailable)
        #expect(PropertyState(of: Property<Int>.unsupported(reason: nil)) == .unsupported)
        #expect(PropertyState(of: Property.uncertain(value: 1, reason: "estimated")) == .uncertain)
        #expect(PropertyState(of: Property<Int>.uncertain(value: nil, reason: "estimated")) == .uncertain)
        #expect(
            PropertyState(of: Property<Int>.failed(PropertyFailure(code: .propertyReadError, message: "x")))
                == .failed
        )
    }

    /// **The reason a value carries never changes its state.** An `uncertain` with a value and one
    /// without are the same state, and a `failed` says nothing about which failure it was — that detail
    /// stays on the property inside the report.
    @Test("the state ignores everything the property carries")
    func stateIgnoresPayloads() {
        #expect(
            PropertyState(of: Property.uncertain(value: 44_100, reason: "a"))
                == PropertyState(of: Property<Int>.uncertain(value: nil, reason: "b"))
        )
        #expect(
            PropertyState(of: Property<Int>.unsupported(reason: "a"))
                == PropertyState(of: Property<Int>.unsupported(reason: nil))
        )
    }

    /// It is **not** `WarningKind`, and the difference is the whole reason it exists.
    @Test("it carries a case WarningKind deliberately does not")
    func itHasAvailableWhereWarningKindDoesNot() {
        // `WarningKind` omits `available` so a warning about a clean property is unrepresentable; the
        // gap needs it so "available against unsupported" can be said at all.
        #expect(allStates.contains(.available))
        #expect(allStates.count == 5)
    }
}

@Suite("Domain — the comparison gap")
struct ComparisonGapTests {

    /// The one invariant: a pair that compares is not a gap.
    @Test("two available states are refused")
    func twoAvailableStatesAreRefused() {
        #expect(ComparisonGap(first: .available, second: .available) == nil)
    }

    /// **The 5 × 5 matrix.** Exactly one of the 25 pairs is invalid, and it is the one above.
    @Test("exactly one of the twenty-five pairs is not a gap")
    func theMatrixHasOneHole() {
        var accepted = 0
        var refused: [(PropertyState, PropertyState)] = []

        for first in allStates {
            for second in allStates {
                if let gap = ComparisonGap(first: first, second: second) {
                    accepted += 1
                    // The two states survive exactly as given, in the order given.
                    #expect(gap.first == first)
                    #expect(gap.second == second)
                } else {
                    refused.append((first, second))
                }
            }
        }

        #expect(accepted == 24)
        #expect(refused.count == 1)
        #expect(refused.first?.0 == .available)
        #expect(refused.first?.1 == .available)
    }

    /// **The order is preserved, never sorted or normalised.** Which side was which is the evidence.
    @Test("the two sides are kept apart and are not interchangeable")
    func theSidesAreNotInterchangeable() throws {
        let oneWay = try #require(ComparisonGap(first: .available, second: .unsupported))
        let other = try #require(ComparisonGap(first: .unsupported, second: .available))

        #expect(oneWay.first == .available)
        #expect(oneWay.second == .unsupported)
        #expect(other.first == .unsupported)
        #expect(other.second == .available)
        // Not equal: the same two states in the other order describe a different situation.
        #expect(oneWay != other)
    }

    /// The combinations the design names explicitly, each constructible and each keeping both states.
    @Test(
        "the named combinations are all valid",
        arguments: [
            (PropertyState.available, PropertyState.unavailable),
            (.unavailable, .available),
            (.unavailable, .unavailable),
            (.unsupported, .available),
            (.unsupported, .unsupported),
            (.uncertain, .uncertain),
            (.failed, .available),
            (.failed, .failed),
        ]
    )
    func namedCombinationsAreValid(first: PropertyState, second: PropertyState) throws {
        let gap = try #require(ComparisonGap(first: first, second: second))
        #expect(gap.first == first)
        #expect(gap.second == second)
    }
}

@Suite("Domain — comparing one property across two files")
struct PropertyComparisonTests {

    // MARK: Both available — the only pair that compares

    @Test("two equal available values are the same, carrying the value once")
    func equalAvailableValuesAreTheSame() {
        let comparison = PropertyComparison(first: Property.available(44_100), second: .available(44_100))
        guard case let .same(value) = comparison else { Issue.record("expected same"); return }
        #expect(value == 44_100)
    }

    @Test("two unequal available values differ, carrying both as evidence")
    func unequalAvailableValuesDiffer() {
        let comparison = PropertyComparison(first: Property.available(44_100), second: .available(48_000))
        guard case let .different(first, second) = comparison else { Issue.record("expected different"); return }
        #expect(first == 44_100)
        #expect(second == 48_000)
    }

    /// **`different` records which value came from which side, and reading a rank into that is the
    /// caller's error, not the type's.** Swapping the two produces a different value, so the evidence
    /// is preserved — and the two are not equal, because they describe different pairs.
    @Test("different keeps the sides in the order they were supplied")
    func differentPreservesTheOrderWithoutRanking() {
        let oneWay = PropertyComparison(first: Property.available(16), second: .available(24))
        let other = PropertyComparison(first: Property.available(24), second: .available(16))

        guard case let .different(a, b) = oneWay, case let .different(c, d) = other else {
            Issue.record("expected different")
            return
        }
        #expect((a, b) == (16, 24))
        #expect((c, d) == (24, 16))
        #expect(oneWay != other)
    }

    // MARK: Everything else — the exhaustive matrix

    /// **The single rule, checked over all 25 pairs**: `(available, available)` compares, and the other
    /// 24 do not, whatever the two properties carry.
    @Test("only two available properties compare; the other twenty-four do not")
    func onlyAvailablePairsCompare() {
        var compared = 0
        var incomparable = 0

        for first in allStates {
            for second in allStates {
                let comparison = PropertyComparison(
                    first: property(first, value: 7),
                    second: property(second, value: 7)
                )
                switch comparison {
                case .same, .different:
                    compared += 1
                    #expect(first == .available && second == .available)
                case let .incomparable(gap):
                    incomparable += 1
                    #expect(!(first == .available && second == .available))
                    // The gap says exactly which states were involved.
                    #expect(gap.first == first)
                    #expect(gap.second == second)
                }
            }
        }

        #expect(compared == 1)
        #expect(incomparable == 24)
    }

    /// **The consequential case, and the one most likely to be "fixed" later.** Two unreliable readings
    /// that happen to agree are still two unreliable readings.
    @Test("two uncertain values are not comparable even when they are equal")
    func twoEqualUncertainValuesAreStillIncomparable() {
        let comparison = PropertyComparison(
            first: Property.uncertain(value: 320_000, reason: "estimated from size and duration"),
            second: .uncertain(value: 320_000, reason: "estimated from size and duration")
        )
        guard case let .incomparable(gap) = comparison else {
            Issue.record("expected incomparable")
            return
        }
        #expect(gap.first == .uncertain)
        #expect(gap.second == .uncertain)
    }

    @Test("an uncertain value is not comparable against an available one, in either order")
    func uncertainAgainstAvailableIsIncomparable() {
        let uncertainFirst = PropertyComparison(
            first: Property.uncertain(value: 5, reason: "estimated"), second: .available(5)
        )
        let availableFirst = PropertyComparison(
            first: Property.available(5), second: .uncertain(value: 5, reason: "estimated")
        )

        guard case let .incomparable(a) = uncertainFirst, case let .incomparable(b) = availableFirst else {
            Issue.record("expected incomparable")
            return
        }
        #expect((a.first, a.second) == (.uncertain, .available))
        #expect((b.first, b.second) == (.available, .uncertain))
    }

    /// **Two absences are not an agreement.** The most tempting shortcut in the whole design.
    @Test("neither file carrying a property is not the same")
    func twoAbsencesAreNotTheSame() {
        let comparison = PropertyComparison(
            first: Property<Int>.unavailable(reason: nil), second: .unavailable(reason: nil)
        )
        guard case let .incomparable(gap) = comparison else { Issue.record("expected incomparable"); return }
        #expect((gap.first, gap.second) == (.unavailable, .unavailable))
    }

    /// A format that cannot express a property stays distinguishable from one that simply lacks it, and
    /// from one whose extraction errored.
    @Test("unsupported, unavailable and failed stay distinguishable")
    func theThreeAbsencesStayApart() {
        let unsupported = PropertyComparison(
            first: Property<Int>.unsupported(reason: "lossy codec"), second: .available(16)
        )
        let unavailable = PropertyComparison(
            first: Property<Int>.unavailable(reason: nil), second: .available(16)
        )
        let failed = PropertyComparison(
            first: Property<Int>.failed(PropertyFailure(code: .propertyReadError, message: "boom")),
            second: .available(16)
        )

        guard case let .incomparable(a) = unsupported,
              case let .incomparable(b) = unavailable,
              case let .incomparable(c) = failed
        else { Issue.record("expected incomparable"); return }

        #expect(a.first == .unsupported)
        #expect(b.first == .unavailable)
        #expect(c.first == .failed)
        #expect(a != b)
        #expect(b != c)
        #expect(a != c)
    }

    /// The payload of an `uncertain` or a `failed` is never consulted, so two comparisons that differ
    /// only in what those cases carry are identical.
    @Test("the payloads of uncertain and failed do not affect the outcome")
    func payloadsDoNotAffectTheOutcome() {
        let one = PropertyComparison(
            first: Property.uncertain(value: 1, reason: "a"), second: Property<Int>.unavailable(reason: nil)
        )
        let other = PropertyComparison(
            first: Property.uncertain(value: 999, reason: "b"), second: Property<Int>.unavailable(reason: "x")
        )
        #expect(one == other)
    }
}

// MARK: - Generic over the value, not tied to any one property

@Suite("Domain — comparison is generic over the value")
struct PropertyComparisonGenericityTests {

    @Test("it compares integers")
    func compareIntegers() {
        #expect(PropertyComparison(first: Property.available(2), second: .available(2)) == .same(2))
        #expect(
            PropertyComparison(first: Property.available(2), second: .available(6))
                == .different(first: 2, second: 6)
        )
    }

    @Test("it compares strings, which is how container and codec are carried")
    func compareStrings() {
        #expect(
            PropertyComparison(first: Property.available("flac"), second: .available("flac"))
                == .same("flac")
        )
        #expect(
            PropertyComparison(first: Property.available("flac"), second: .available("wav"))
                == .different(first: "flac", second: "wav")
        )
    }

    /// **Duration gets no special treatment, and that is the decision.** A `Double` falls through the
    /// same generic rule as everything else, so equality is exact: there is nowhere for a tolerance,
    /// an epsilon or a rounding step to live.
    @Test("it compares doubles exactly, with no tolerance anywhere")
    func compareDoublesExactly() {
        #expect(
            PropertyComparison(first: Property.available(180.0), second: .available(180.0))
                == .same(180.0)
        )

        // Musically identical copies differing by the smallest representable amount are `different`.
        // That is the honest answer about the declared fact, and says nothing about the audio.
        let barelyLonger = 180.0.nextUp
        let comparison = PropertyComparison(first: Property.available(180.0), second: .available(barelyLonger))
        #expect(comparison == .different(first: 180.0, second: barelyLonger))

        // One frame at 44.1 kHz is enormous next to that, and is likewise just `different`.
        #expect(
            PropertyComparison(first: Property.available(180.0), second: .available(180.0 + 1.0 / 44_100))
                != .same(180.0)
        )
    }

    /// The type stores a value it cannot compare; only building one needs `Equatable`. Nothing here
    /// requires `Comparable`, and nothing could use it.
    @Test("storing a value needs no equality at all")
    func storingNeedsNoEquality() {
        struct Opaque { let token: String }
        let stored = PropertyComparison.same(Opaque(token: "held"))
        guard case let .same(value) = stored else { Issue.record("expected same"); return }
        #expect(value.token == "held")
    }
}

// MARK: - What these types must not be able to do

/// **Absences, checked where a check is real and recorded where it is not.**
///
/// Two of the prohibitions in ADR-0017 are conformances, and a conformance is a fact about the type at
/// runtime — asking whether it exists is a genuine question with a genuine answer. Those are tested
/// below.
///
/// The rest — that no member is called `winner`, `preferred`, `score`, `similarity`, `isBetter`,
/// `allSame` or anything of that shape — **cannot be tested honestly.** Swift exposes no reflection
/// over a type's methods, so the only "test" available would assert that a string does not appear in a
/// file, which proves nothing about behaviour and would pass just as happily against a member spelled
/// differently. It is therefore an **audit** carried by the type's own documentation and by review, and
/// is deliberately not dressed up as a test here. Writing a green check that establishes nothing would
/// be worse than the gap it hides.
@Suite("Domain — comparison prohibitions")
struct ComparisonProhibitionTests {

    /// **No ordering.** If the type conformed to `Comparable`, this cast would succeed and one file
    /// could be sorted above the other.
    @Test("no comparison type is Comparable")
    func nothingIsComparable() {
        #expect(!(PropertyComparison<Int>.self is any Comparable.Type))
        #expect(!(PropertyComparison<Double>.self is any Comparable.Type))
        #expect(!(PropertyComparison<String>.self is any Comparable.Type))
        #expect(!(ComparisonGap.self is any Comparable.Type))
        #expect(!(PropertyState.self is any Comparable.Type))
    }

    /// **Nothing reaches the exporter.** `schemaVersion` 1 describes one file; a comparison type that
    /// could encode itself would advertise a contract that does not exist.
    @Test("no comparison type is Codable")
    func nothingIsCodable() {
        #expect(!(PropertyComparison<Int>.self is any Encodable.Type))
        #expect(!(PropertyComparison<Int>.self is any Decodable.Type))
        #expect(!(PropertyComparison<String>.self is any Encodable.Type))
        #expect(!(ComparisonGap.self is any Encodable.Type))
        #expect(!(ComparisonGap.self is any Decodable.Type))
        #expect(!(PropertyState.self is any Encodable.Type))
        #expect(!(PropertyState.self is any Decodable.Type))
    }

    /// What the types *are*, demonstrated by **use** rather than by a runtime cast.
    ///
    /// A cast would work, but the compiler rejects it as *"always true"* — and that rejection is the
    /// point: where a conformance exists, it is proved **statically**, which is a stronger guarantee
    /// than any check this test could run. So these are exercised through generic functions that will
    /// not compile if a conformance is ever dropped.
    @Test("the intended conformances are present and usable")
    func theIntendedConformancesArePresent() {
        func requiresSendable<T: Sendable>(_ value: T) -> T { value }
        func requiresEquatable<T: Equatable>(_ one: T, _ other: T) -> Bool { one == other }

        let comparison = PropertyComparison.same(44_100)
        let gap = ComparisonGap(first: .available, second: .failed)

        #expect(requiresEquatable(requiresSendable(comparison), .same(44_100)))
        #expect(requiresEquatable(requiresSendable(gap), gap))
        #expect(requiresEquatable(requiresSendable(PropertyState.available), .available))

        // Conditional, exactly as `Property`'s are: a value that is not `Equatable` still stores.
        struct Opaque: Sendable { let token: String }
        _ = requiresSendable(PropertyComparison.same(Opaque(token: "held")))
    }
}
