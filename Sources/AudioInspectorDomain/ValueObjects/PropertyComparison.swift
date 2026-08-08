/// The structural state of **one side** of a comparison, with no value and no explanation attached.
///
/// It exists because `ComparisonGap` has to be able to say *"this side was available and that one was
/// not"*, and therefore needs a case for `available` — which is exactly the case `WarningKind`
/// deliberately omits, so that a warning about a cleanly available property is unrepresentable. **The
/// two types are different on purpose and must not be unified**: one describes a situation worth
/// warning about, this one describes which of the five states a property was in.
///
/// **It deliberately carries nothing else.** No `reason`, no `PropertyFailure`, no value. Those live on
/// the `Property` this was derived from, inside the report that produced it, and copying them here
/// would create a second copy able to drift from the first. A caller that wants to say more than *"the
/// format cannot express it"* reads the property itself.
public enum PropertyState: Sendable, Equatable {
    case available
    case unavailable
    case unsupported
    case uncertain
    case failed
}

extension PropertyState {
    /// The state of `property`, total over every case.
    ///
    /// **Internal on purpose.** Presentation reads a finished `PropertyComparison`, never this mapping,
    /// and `Property` gains nothing — the inspection types are not modified by this slice. The switch
    /// has exactly one home, so no field can be classified two different ways.
    init<Value>(of property: Property<Value>) {
        switch property {
        case .available: self = .available
        case .unavailable: self = .unavailable
        case .unsupported: self = .unsupported
        case .uncertain: self = .uncertain
        case .failed: self = .failed
        }
    }
}

/// Why two properties could not be compared: the state each side was in, and nothing more.
///
/// ## Why this is a type rather than two loose parameters
///
/// For one reason only. Two `available` states describe a pair that **is** comparable, so a gap holding
/// them would contradict itself, and leaving that representable would give up exactly the guarantee
/// `Property`'s own design buys (ADR-0008). The failable initialiser refuses it — the device
/// `WaveformBucket.init?` already uses to refuse a bucket it could not describe honestly. Without that
/// invariant to enforce, the two states on their own would have been the right shape.
///
/// ## The two states are kept exactly, never summarised
///
/// There is no `missing`, no `oneSideMissing`, no `bothMissing`. *"This format cannot express bit
/// depth"* and *"reading bit depth errored"* are different things to tell a person, and they are
/// already distinct one level down; collapsing them here would throw that away for a shorter enum.
///
/// The order is the order the sides were supplied — **the file already open, then the file chosen for
/// comparison**. It carries no rank, and nothing here derives one from it.
public struct ComparisonGap: Sendable, Equatable {
    public let first: PropertyState
    public let second: PropertyState

    /// Fails when both sides are `available`, because that pair is comparable and is therefore not a
    /// gap. Every other combination of the five states is valid — 24 of the 25.
    public init?(first: PropertyState, second: PropertyState) {
        guard !(first == .available && second == .available) else { return nil }
        self.first = first
        self.second = second
    }

    /// Builds a gap **without** checking the invariant, for the one caller that has already excluded the
    /// contradictory pair by construction.
    ///
    /// `fileprivate`, so it cannot be reached from outside this file: `PropertyComparison`'s rule
    /// matches two `available` properties in an earlier branch, so by the time this runs the pair
    /// provably cannot be `(.available, .available)`. Using the failable initialiser there would force
    /// either a force-unwrap or an unreachable fallback that lies about what it means.
    fileprivate init(uncheckedFirst: PropertyState, second: PropertyState) {
        first = uncheckedFirst
        self.second = second
    }
}

/// What comparing one technical property across two files establishes.
///
/// Three cases, exhaustive, in the shape `Property` established for a single property (ADR-0008): the
/// two agree, the two differ, or nothing was compared. **The third is a first-class outcome, not an
/// error and not a gap in the data** — when one file's format cannot express bit depth and the other's
/// can, the honest answer is that nothing was compared, and reporting a difference would manufacture a
/// fact out of an absence.
///
/// ## What it cannot express, structurally
///
/// A comparison is an observation, never a judgement (ADR-0017). So there is **no ordering, no delta,
/// no ratio, no preferred side, no winner, no score and no confidence** — not by convention, but
/// because no case and no member can carry one. In particular this type does **not** conform to
/// `Comparable`, exposes no accessor that returns one of the two values in preference to the other, and
/// offers no summary of a whole comparison: *"every comparable property agreed"* and *"the two files
/// are the same"* are different statements, and a single boolean would blur them.
///
/// `different` carries both values **as the evidence for that statement** and nothing else. The labels
/// are the order the sides were supplied, and mean no more than that.
///
/// ## Not `Codable`
///
/// Like `Spectrogram`, it never enters the `schemaVersion` 1 export; conforming it would advertise a
/// contract that does not exist.
public enum PropertyComparison<Value> {
    /// Both sides carried an available value and the values are equal. Carried once, because both
    /// sides hold it.
    case same(Value)

    /// Both sides carried an available value and the values are not equal.
    case different(first: Value, second: Value)

    /// Nothing was compared. Carries the state each side was in.
    case incomparable(ComparisonGap)
}

extension PropertyComparison: Sendable where Value: Sendable {}
extension PropertyComparison: Equatable where Value: Equatable {}

public extension PropertyComparison where Value: Equatable {
    /// **The single rule, written once**, so no field can drift from it.
    ///
    /// Two properties compare **only** when both are `available`. Every other combination — in either
    /// order, and whatever the two sides carry — is `incomparable`.
    ///
    /// **`uncertain` is inside that exclusion, and there is no exception for two `uncertain` values
    /// that happen to be equal.** A value read but not reliable is not a comparable fact, and reporting
    /// a coincidence between two unreliable readings as agreement would promote both to something they
    /// are not. The payloads of `uncertain` and `failed` are therefore never consulted here.
    ///
    /// Equality is the field's own, exact: a `Double` duration compares by `==`, with no tolerance,
    /// no rounding and no conversion. That is a decision (ADR-0017), and it is enforced by there being
    /// nowhere for a special case to live — every field falls through this one generic rule.
    init(first: Property<Value>, second: Property<Value>) {
        switch (first, second) {
        case let (.available(firstValue), .available(secondValue)):
            self = firstValue == secondValue
                ? .same(firstValue)
                : .different(first: firstValue, second: secondValue)
        default:
            // The branch above has taken the only pair a gap refuses, so the unchecked initialiser
            // cannot produce a contradictory one here.
            self = .incomparable(ComparisonGap(
                uncheckedFirst: PropertyState(of: first),
                second: PropertyState(of: second)
            ))
        }
    }
}
