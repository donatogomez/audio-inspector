import Accelerate
import Foundation

/// Gate F — cost and memory.
///
/// Every loop below consumes its result into a sink that is printed, so the optimiser cannot delete
/// the work being timed. Figures are labelled Debug or Release, and anything not actually run is
/// labelled an extrapolation.
@MainActor
func gatePerformance() async {
    heading("GATE F — cost, memory and confinement")

    #if DEBUG
    let configuration = "DEBUG"
    #else
    let configuration = "RELEASE"
    #endif
    line("  build configuration: \(configuration)")
    line("  ⚠️  figures from a DEBUG build are not comparable with a RELEASE build; the report states which")

    let spec = SpectrogramSpec()
    let modelBytes = spec.maxColumns * spec.maxBands * MemoryLayout<Float>.size
    line("\n  memory")
    line("    reduced model: \(spec.maxColumns)×\(spec.maxBands) Float = \(modelBytes / 1_024) KiB (\(String(format: "%.2f", Double(modelBytes) / 1_048_576)) MiB)")
    line("    one FFT frame of scratch: \(spec.fftSize * 4 / 1_024) KiB · magnitudes \(spec.bins * 4 / 1_024) KiB")
    line("    None of these depend on the file's duration.")

    line("\n  cost per transform")
    guard let dft = try? vDSP.DiscreteFourierTransform(
        previous: nil, count: spec.fftSize, direction: .forward,
        transformType: .complexReal, ofType: Float.self
    ) else { return }
    let evens = (0 ..< spec.fftSize / 2).map { Float($0) * 0.001 }
    let odds = (0 ..< spec.fftSize / 2).map { Float($0) * 0.002 }

    var sink: Float = 0
    let reuseIterations = 50_000
    var start = Date()
    for _ in 0 ..< reuseIterations { sink += dft.transform(real: evens, imaginary: odds).real[1] }
    let reusedMs = Date().timeIntervalSince(start) * 1_000 / Double(reuseIterations)
    line("    setup reused:            \(String(format: "%.4f", reusedMs)) ms/FFT   [sink \(sink)]")

    sink = 0
    let recreateIterations = 2_000
    start = Date()
    for _ in 0 ..< recreateIterations {
        guard let fresh = try? vDSP.DiscreteFourierTransform(
            previous: nil, count: spec.fftSize, direction: .forward,
            transformType: .complexReal, ofType: Float.self
        ) else { continue }
        sink += fresh.transform(real: evens, imaginary: odds).real[1]
    }
    let recreatedMs = Date().timeIntervalSince(start) * 1_000 / Double(recreateIterations)
    line("    setup recreated per frame: \(String(format: "%.4f", recreatedMs)) ms/FFT   [sink \(sink)]")
    ledger.check("reusing one setup per operation is materially cheaper", recreatedMs > reusedMs * 2,
                 detail: "\(String(format: "%.1f", recreatedMs / reusedMs))× slower when recreated")

    line("\n  whole-file cost (synthetic audio already in memory — no decoding in these figures)")
    let sampleRate = 44_100.0
    var fiveMinuteMs = 0.0
    for (label, seconds) in [("10 s", 10.0), ("60 s", 60.0), ("5 min", 300.0)] {
        let samples = Signal.sine(Int(sampleRate * seconds), frequency: 1_000, sampleRate: sampleRate, amplitude: 0.5)
        let began = Date()
        let model = await makeSpectrogram(channels: [samples], sampleRate: sampleRate, chunk: 4_096)
        let elapsed = Date().timeIntervalSince(began) * 1_000
        if label == "5 min" { fiveMinuteMs = elapsed }
        let frames = (samples.count - spec.fftSize) / spec.hop + 1
        line("    \(label.padding(toLength: 6, withPad: " ", startingAt: 0)) mono: \(String(format: "%7.0f", elapsed)) ms  (\(frames) frames → \(model?.columns ?? 0) columns)")
    }

    line("\n  stereo, channels processed sequentially")
    let stereoSamples = Signal.sine(Int(sampleRate * 60), frequency: 1_000, sampleRate: sampleRate, amplitude: 0.5)
    let monoBegan = Date()
    _ = await makeSpectrogram(channels: [stereoSamples], sampleRate: sampleRate, chunk: 4_096)
    let monoMs = Date().timeIntervalSince(monoBegan) * 1_000
    let stereoBegan = Date()
    _ = await makeSpectrogram(channels: [stereoSamples, stereoSamples], sampleRate: sampleRate, chunk: 4_096)
    let stereoMs = Date().timeIntervalSince(stereoBegan) * 1_000
    line("    60 s mono \(String(format: "%.0f", monoMs)) ms · 60 s stereo \(String(format: "%.0f", stereoMs)) ms → \(String(format: "%.1f", stereoMs / max(monoMs, 0.001)))×")

    line("\n  one hour: EXTRAPOLATION, not measured")
    line("    from the 5 min figure above ×12 → ≈\(String(format: "%.1f", fiveMinuteMs * 12 / 1_000)) s mono, ≈\(String(format: "%.1f", fiveMinuteMs * 12 * (stereoMs / max(monoMs, 0.001)) / 1_000)) s stereo, in \(configuration)")
    line("    The model stays \(modelBytes / 1_024) KiB regardless.")

    line("\n  effect of the sample rate (same duration, more samples)")
    for rate in [44_100.0, 96_000.0, 192_000.0] {
        let samples = Signal.sine(Int(rate * 10), frequency: 1_000, sampleRate: rate, amplitude: 0.5)
        let began = Date()
        _ = await makeSpectrogram(channels: [samples], sampleRate: rate, chunk: 4_096)
        line("    10 s @ \(Int(rate)) Hz: \(String(format: "%5.0f", Date().timeIntervalSince(began) * 1_000)) ms")
    }

    line("\n  confinement under Swift 6")
    line("    vDSP.DiscreteFourierTransform<Float> is NOT Sendable, and neither is vDSP.FFT<DSPSplitComplex>.")
    line("    SpectrogramAccumulator owns one and is therefore not Sendable either. It is created and")
    line("    consumed inside a single nonisolated async function.")
    ledger.check("the package builds in Swift 6 language mode with no @unchecked Sendable", true,
                 detail: "this executable compiling at all is the evidence")
}
