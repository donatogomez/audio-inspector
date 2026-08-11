import Foundation

/// The cost matrix, in its own file so it can be run **alone** — `--cost-only` skips every analysis
/// phase. That matters for the unoptimised build, where the analysis phases take many minutes and
/// contribute nothing the optimised run has not already shown.
///
/// Decode is deliberately **not** measured here: this package imports no AVFoundation, and the
/// project already has a decode figure measured against a real ten-minute stereo file
/// (`SignalLevelMetricsAccumulator`'s own documentation: 0.035 s). Re-measuring it through a
/// hand-written WAV reader would produce a different number for a different operation.
func runCostPhase(quick: Bool) {
    heading("PHASE H — cost (44.1 kHz; true-peak DSP only — decode not included, see the report)")
    print("duration | channels | design | implementation | seconds")
    let designs: [(String, Method)] = [
        ("32tap-b6-4x", .fir(factor: 4, tapsPerPhase: 32, beta: 6)),
        ("48tap-b6-4x", .fir(factor: 4, tapsPerPhase: 48, beta: 6)),
        ("48tap-b6-8x", .fir(factor: 8, tapsPerPhase: 48, beta: 6)),
    ]
    // Debug runs a reduced matrix on purpose: a scalar `Double` pass over ten minutes in an
    // unoptimised build takes minutes and would tell us nothing the one-minute run does not.
    let durations = quick ? [1] : [1, 10]
    for minutes in durations {
        let frames = 44_100 * 60 * minutes
        let signal = (0 ..< frames).map { n -> Double in
            let t = Double(n) / 44_100
            return 0.7 * sin(2 * .pi * 997 * t + .pi / 4) + 0.2 * sin(2 * .pi * 3_001 * t)
        }
        for channels in [1, 2] {
            for (label, method) in designs {
                let filter = PolyphaseFilter(method: method)
                for implementation in ["scalar-double", "scalar-float", "vdsp"] {
                    let elapsed = ContinuousClock().measure {
                        for _ in 0 ..< channels {
                            switch implementation {
                            case "scalar-double": _ = Reconstruct.peakDouble(signal, filter: filter, edge: .zero)
                            case "scalar-float": _ = Reconstruct.peakFloat(signal, filter: filter, edge: .zero)
                            default: _ = Reconstruct.peakVDSP(signal, filter: filter, edge: .zero)
                            }
                        }
                    }
                    print("\(minutes) min | \(channels) | \(label) | \(implementation) | \(seconds(elapsed))")
                }
            }
        }
    }
    // The vDSP path alone over ten minutes — the only combination the unoptimised build needs at
    // length, since Accelerate is precompiled and does not slow down with `-Onone`.
    if quick {
        let frames = 44_100 * 60 * 10
        let signal = (0 ..< frames).map { n in 0.7 * sin(2 * .pi * 997 * Double(n) / 44_100 + .pi / 4) }
        for (label, method) in designs {
            let filter = PolyphaseFilter(method: method)
            let elapsed = ContinuousClock().measure {
                for _ in 0 ..< 2 { _ = Reconstruct.peakVDSP(signal, filter: filter, edge: .zero) }
            }
            print("10 min | 2 | \(label) | vdsp | \(seconds(elapsed))")
        }
    }
}

private func seconds(_ duration: Duration) -> String {
    let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    return String(format: "%.3f", value)
}
