/// A single technical property together with its availability and certainty.
///
/// This is an **exhaustive sum type** (ADR-0008): the state *is* the case, so invalid combinations
/// (a value with `unsupported`, a `failed` with a value, an `uncertain` without a reason, …) are
/// unrepresentable by construction. It carries no JSON/`Codable` concepts — the flat wire shape is
/// produced by the export layer's mapper, not here.
///
/// Conforms to `Sendable`/`Equatable` only when `Value` does (conditional conformance).
public enum Property<Value> {
    /// A trustworthy value is present.
    case available(Value)

    /// The file/format simply does not carry this property.
    case unavailable(reason: String?)

    /// The format cannot express this property (e.g. bit depth for a lossy codec).
    case unsupported(reason: String?)

    /// A value was read but is not reliable. `reason` is required; `value` is optional.
    case uncertain(value: Value?, reason: String)

    /// Extracting this specific property errored. Carries a **property-level** failure
    /// (`PropertyFailure`), distinct from the global `InspectionError`.
    case failed(PropertyFailure)
}

extension Property: Sendable where Value: Sendable {}
extension Property: Equatable where Value: Equatable {}

public extension Property {
    /// The carried value, if any — present only for `available` and `uncertain`; `nil` otherwise.
    var value: Value? {
        switch self {
        case let .available(value): value
        case let .uncertain(value, _): value
        case .unavailable, .unsupported, .failed: nil
        }
    }
}
