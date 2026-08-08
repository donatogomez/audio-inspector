/// The structural state of **one side** of a comparison, with no value and no explanation attached.
///
/// It exists because a comparison has to be able to say *"this side was available and that one was
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

/// The four states that are **not** `available` — the ones that leave a side with no comparable value.
///
/// A separate type rather than a convention, because it is what makes a contradictory
/// `ComparisonGap` impossible to write down at all (see `ComparisonGap`). Splitting the five states
/// into "available" and "these four" is the whole mechanism.
///
/// **It is not `WarningKind` either**, though today they carry the same four names. `WarningKind`
/// describes a situation worth warning a reader about; this describes why a side of a comparison had
/// nothing to compare. They are free to diverge, and unifying them would couple the comparison
/// vocabulary to the warning vocabulary for no reason beyond a coincidence of spelling.
public enum NonAvailableState: Sendable, Equatable {
    case unavailable
    case unsupported
    case uncertain
    case failed
}

public extension PropertyState {
    /// This state as a non-available one, or `nil` when it is `available`.
    var nonAvailable: NonAvailableState? {
        switch self {
        case .available: nil
        case .unavailable: .unavailable
        case .unsupported: .unsupported
        case .uncertain: .uncertain
        case .failed: .failed
        }
    }

    /// The state a non-available one describes, widened back to the full five.
    init(_ state: NonAvailableState) {
        switch state {
        case .unavailable: self = .unavailable
        case .unsupported: self = .unsupported
        case .uncertain: self = .uncertain
        case .failed: self = .failed
        }
    }
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
/// ## The invariant is the shape, not a check
///
/// Two `available` states describe a pair that **is** comparable, so a gap holding them would
/// contradict itself. Rather than accept that pair and reject it at runtime, the three cases below
/// make it **impossible to write down**: every case names at least one side as non-available, so
/// `(available, available)` has no spelling. 4 + 4 + 16 = **24 combinations, which is exactly the 24
/// that are gaps**, and the twenty-fifth does not exist rather than being refused.
///
/// That is worth more than a failable initialiser. A refusal has to be reached to work, and a caller
/// that has already proved the pair is impossible then needs either a force-unwrap or an unreachable
/// branch. Here there is nothing to prove and nothing to unwrap: the compiler carries it.
///
/// ## The two states are kept exactly, never summarised
///
/// `first` and `second` reconstruct the pair, so nothing is lost by the shape. There is no `missing`,
/// no `oneSideMissing`, no `bothMissing`: *"this format cannot express bit depth"* and *"reading bit
/// depth errored"* are different things to tell a person, they are already distinct one level down,
/// and collapsing them here would throw that away for a shorter enum.
///
/// The order is the order the sides were supplied — **the file already open, then the file chosen for
/// comparison**. It carries no rank, and nothing here derives one from it.
public enum ComparisonGap: Sendable, Equatable {
    /// The first side had a value; the second did not.
    case firstAvailable(second: NonAvailableState)
    /// The second side had a value; the first did not.
    case secondAvailable(first: NonAvailableState)
    /// Neither side had a value.
    case neitherAvailable(first: NonAvailableState, second: NonAvailableState)
}

public extension ComparisonGap {
    /// The state the first side was in.
    var first: PropertyState {
        switch self {
        case .firstAvailable: .available
        case let .secondAvailable(state): PropertyState(state)
        case let .neitherAvailable(state, _): PropertyState(state)
        }
    }

    /// The state the second side was in.
    var second: PropertyState {
        switch self {
        case let .firstAvailable(state): PropertyState(state)
        case .secondAvailable: .available
        case let .neitherAvailable(_, state): PropertyState(state)
        }
    }

    /// The gap between two states, or `nil` when both are `available` — the one pair that is not a gap.
    ///
    /// A convenience for a caller holding two `PropertyState`s. The comparison rule does **not** use it:
    /// it builds a case directly, because it already knows which side was which.
    init?(first: PropertyState, second: PropertyState) {
        switch (first.nonAvailable, second.nonAvailable) {
        case (nil, nil):
            return nil
        case let (nil, .some(secondState)):
            self = .firstAvailable(second: secondState)
        case let (.some(firstState), nil):
            self = .secondAvailable(first: firstState)
        case let (.some(firstState), .some(secondState)):
            self = .neitherAvailable(first: firstState, second: secondState)
        }
    }
}

/// One side of a comparison, split so the compiler can see that a pair which is not two values is a
/// gap. Total over every `Property`: each one is either a value or a reason there is none.
///
/// Private, and the whole reason the rule below needs no force-unwrap, no unchecked initialiser and no
/// unreachable branch.
private enum ComparisonSide<Value> {
    case value(Value)
    case gap(NonAvailableState)

    init(of property: Property<Value>) {
        switch property {
        case let .available(value): self = .value(value)
        case .unavailable: self = .gap(.unavailable)
        case .unsupported: self = .gap(.unsupported)
        case .uncertain: self = .gap(.uncertain)
        case .failed: self = .gap(.failed)
        }
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
    ///
    /// **Every branch below constructs its result outright.** Splitting each side into a value or a
    /// reason there is none leaves the four cases the compiler can check, and each one already knows
    /// which side was which — so there is no invariant to re-establish, nothing to unwrap and no
    /// branch that cannot happen.
    init(first: Property<Value>, second: Property<Value>) {
        switch (ComparisonSide(of: first), ComparisonSide(of: second)) {
        case let (.value(firstValue), .value(secondValue)):
            self = firstValue == secondValue
                ? .same(firstValue)
                : .different(first: firstValue, second: secondValue)
        case let (.value, .gap(secondState)):
            self = .incomparable(.firstAvailable(second: secondState))
        case let (.gap(firstState), .value):
            self = .incomparable(.secondAvailable(first: firstState))
        case let (.gap(firstState), .gap(secondState)):
            self = .incomparable(.neitherAvailable(first: firstState, second: secondState))
        }
    }
}
