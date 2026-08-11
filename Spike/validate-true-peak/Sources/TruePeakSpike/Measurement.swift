import Foundation

/// What one true-peak measurement produces, per the contract `design.md` §2.1 and §7 describe.
///
/// Linear internally; dBTP exists only for human inspection, exactly as the production design says it
/// will (`HumanFormat`'s job, never the model's).
struct TruePeakResult {
    struct Channel {
        let sampleCount: Int
        /// `max |x[n]|` over the stored samples. `nil` iff `sampleCount == 0`.
        let samplePeak: Double?
        /// `max |x(t)|` over the reconstruction. `nil` iff `sampleCount == 0`.
        let truePeak: Double?
    }

    let channels: [Channel]
    let method: Method

    /// Maximum of the per-channel values — exact, because a maximum of maxima is the maximum.
    var overallSamplePeak: Double? { channels.compactMap(\.samplePeak).max() }
    var overallTruePeak: Double? { channels.compactMap(\.truePeak).max() }

    /// dBTP for reading, never for storing. `-inf` is floored the way the app already floors dBFS.
    static func decibels(_ linear: Double?) -> String {
        guard let linear else { return "n/c" }
        let floorDecibels = -120.0
        let value = linear > 0 ? max(floorDecibels, 20 * log10(linear)) : floorDecibels
        return String(format: "%+.4f", value)
    }
}

/// The methodology that produced a value — the thing ADR-0006 requires to travel with the result and
/// ADR-0019 decides lives inside the measurement.
struct Method: Equatable, CustomStringConvertible {
    enum Kind: String { case polyphaseFIR, frequencyDomain, none }

    let kind: Kind
    let oversamplingFactor: Int
    /// Taps **per phase**. Total filter length is `tapsPerPhase * oversamplingFactor`.
    let tapsPerPhase: Int
    /// Kaiser window β. The window is evaluated on the sinc's own argument, normalised by the half-width.
    let kaiserBeta: Double
    /// Sinc cutoff as a fraction of the *input* Nyquist. 1.0 = the full original band.
    let cutoff: Double
    /// Whether each phase's taps are scaled to sum to exactly 1 (DC gain preserved per phase).
    let normalisePhases: Bool
    let edge: EdgeHandling
    let precision: Precision

    var identifier: String {
        switch kind {
        case .none: "none"
        case .frequencyDomain: "fft-zero-pad-\(oversamplingFactor)x"
        case .polyphaseFIR:
            "polyphase-fir-\(oversamplingFactor)x-\(tapsPerPhase)tap-kaiser\(String(format: "%.1f", kaiserBeta))"
                + "-cut\(String(format: "%.2f", cutoff))\(normalisePhases ? "-norm" : "")"
        }
    }

    var description: String { "\(identifier) edge=\(edge.rawValue) precision=\(precision.rawValue)" }

    static func fir(
        factor: Int,
        tapsPerPhase: Int = 12,
        beta: Double = 8.6,
        cutoff: Double = 1.0,
        normalise: Bool = true,
        edge: EdgeHandling = .zero,
        precision: Precision = .double
    ) -> Method {
        Method(
            kind: .polyphaseFIR, oversamplingFactor: factor, tapsPerPhase: tapsPerPhase,
            kaiserBeta: beta, cutoff: cutoff, normalisePhases: normalise, edge: edge, precision: precision
        )
    }

    static func fft(factor: Int) -> Method {
        Method(
            kind: .frequencyDomain, oversamplingFactor: factor, tapsPerPhase: 0, kaiserBeta: 0,
            cutoff: 1, normalisePhases: false, edge: .periodic, precision: .float
        )
    }
}

/// What the reconstruction assumes exists beyond the first and last stored sample.
enum EdgeHandling: String {
    /// Silence outside the file — what a decoder handing the file to anything else also produces.
    case zero
    /// The signal mirrored about the first and last sample.
    case mirror
    /// The first/last sample held constant outside the file.
    case constant
    /// No extension at all: only output points the filter fully covers are evaluated.
    case interiorOnly = "interior-only"
    /// Circular, inherent to the frequency-domain candidate.
    case periodic
}

enum Precision: String { case float, double }
