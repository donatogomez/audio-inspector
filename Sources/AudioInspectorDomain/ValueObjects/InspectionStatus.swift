/// The global outcome of an inspection.
///
/// Modelled as a sum type so that state and error can never contradict: only `failed` carries an
/// `InspectionError`; `completed` and `partial` cannot carry one.
public enum InspectionStatus: Sendable, Equatable {
    /// Every property the format exposes was read.
    case completed

    /// Some properties were available, others unavailable/unsupported/uncertain.
    case partial(message: String?)

    /// The file could not be inspected at all; carries a stable error.
    case failed(InspectionError)
}
