import Accelerate
import Foundation

/// Deterministic test signals. Every one is a pure function of its parameters, so a rerun reproduces
/// the report's numbers exactly. Nothing here reads a file and nothing is random without a seed.
enum Signal {
    static func silence(_ count: Int) -> [Float] { [Float](repeating: 0, count: count) }

    static func dc(_ count: Int, level: Float) -> [Float] { [Float](repeating: level, count: count) }

    static func sine(_ count: Int, frequency: Double, sampleRate: Double, amplitude: Float) -> [Float] {
        (0 ..< count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    static func impulse(_ count: Int, at index: Int, amplitude: Float) -> [Float] {
        var samples = silence(count)
        if index >= 0, index < count { samples[index] = amplitude }
        return samples
    }

    static func sum(_ lhs: [Float], _ rhs: [Float]) -> [Float] { zip(lhs, rhs).map(+) }

    /// White noise from a seeded LCG, so runs are bit-reproducible.
    static func noise(_ count: Int, amplitude: Float, seed: UInt64 = 42) -> [Float] {
        var state = seed
        return (0 ..< count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return amplitude * (Float(state >> 33) / Float(UInt32.max >> 1) - 1)
        }
    }

    /// Brick-wall low pass applied in the frequency domain, so the cutoff is exact and known rather
    /// than the roll-off of some filter design. `count` must be a power of two.
    static func lowPassed(_ input: [Float], cutoff: Double, sampleRate: Double) -> [Float] {
        let count = input.count
        let log2n = vDSP_Length(log2(Float(count)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return input }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = input
        var imaginary = [Float](repeating: 0, count: count)
        var output = [Float](repeating: 0, count: count)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                let cutBin = Int(cutoff / (sampleRate / Double(count)))
                for index in 0 ..< count where min(index, count - index) > cutBin {
                    realPointer[index] = 0
                    imaginaryPointer[index] = 0
                }
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                for index in 0 ..< count { output[index] = realPointer[index] / Float(count) }
            }
        }
        return output
    }
}

// MARK: - Reporting helpers

func line(_ text: String) { print(text) }

func heading(_ text: String) {
    print("\n═══ \(text) ═══")
}

func verdict(_ passed: Bool) -> String { passed ? "PASS" : "FAIL" }

/// Records every claim so the run ends with a count rather than a reader's impression.
///
/// `@MainActor` because it is mutable shared state reached from top-level code, which Swift 6 puts on
/// the main actor. Swift 6 rejected it as a bare global, which is the correct diagnosis rather than an
/// inconvenience — so it is isolated instead of being made `@unchecked Sendable`.
@MainActor
final class Ledger {
    private(set) var passed = 0
    private(set) var failed = 0
    private(set) var skipped: [String] = []

    func check(_ label: String, _ passed: Bool, detail: String = "") {
        if passed { self.passed += 1 } else { failed += 1 }
        let suffix = detail.isEmpty ? "" : "  — \(detail)"
        print("    [\(verdict(passed))] \(label)\(suffix)")
    }

    func skip(_ label: String, reason: String) {
        skipped.append(label)
        print("    [SKIP] \(label) — \(reason)")
    }

    func summary() {
        print("\n═══ ledger ═══")
        print("  passed: \(passed)   failed: \(failed)   skipped: \(skipped.count)")
        for item in skipped { print("    skipped: \(item)  ← NOT evidence") }
        if failed > 0 { print("  ⚠️  the spike did not fully reproduce; the report must say so") }
    }
}

@MainActor let ledger = Ledger()
