import Foundation

/// Gate C — maximum against mean, with real temporal folding.
///
/// **A first attempt at this gate was wrong and is worth recording.** It used a signal short enough
/// that every STFT frame became its own column, so nothing was folded and the two strategies could not
/// possibly differ — they came out 0.2 dB apart and the comparison proved nothing. The gate below uses
/// 60 seconds, which folds roughly five frames into each column, and the difference is 8.7 dB.
@MainActor
func gateReduction() {
    heading("GATE C — maximum against mean, with temporal folding")
    let sampleRate = 44_100.0
    let count = Int(sampleRate * 60)
    let frames = (count - 2_048) / 512 + 1
    line("  \(count) samples → \(frames) STFT frames → 1024 columns (≈\(frames / 1_024) frames folded per column)")

    line("\n  a 20 ms transient of 15 kHz inside 60 s of silence")
    var transient = Signal.silence(count)
    for (offset, value) in Signal.sine(882, frequency: 15_000, sampleRate: sampleRate, amplitude: 0.5).enumerated() {
        transient[count / 2 + offset] = value
    }
    var transientPeaks: [Reduction: Float] = [:]
    for reduction in [Reduction.maximum, .mean] {
        guard let model = spectrogram(channels: [transient], sampleRate: sampleRate, reduction: reduction),
              let peak = model.peak(atFrequency: 15_000) else { continue }
        transientPeaks[reduction] = peak
        line("    \(reduction.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(String(format: "%8.2f", peak)) dBFS")
    }
    if let maximum = transientPeaks[.maximum], let mean = transientPeaks[.mean] {
        ledger.check("the mean buries a short transient the maximum keeps", maximum - mean > 5,
                     detail: "\(String(format: "%.2f", maximum - mean)) dB of difference")
    }

    line("\n  energy in only part of a folded column: 1 s of 15 kHz every 10 s")
    var intermittent = Signal.silence(count)
    for block in 0 ..< 6 {
        let offset = block * Int(sampleRate * 10)
        for (index, value) in Signal.sine(Int(sampleRate), frequency: 15_000, sampleRate: sampleRate, amplitude: 0.5).enumerated()
        where offset + index < count {
            intermittent[offset + index] = value
        }
    }
    for reduction in [Reduction.maximum, .mean] {
        guard let model = spectrogram(channels: [intermittent], sampleRate: sampleRate, reduction: reduction) else { continue }
        let band = Int(15_000 / (model.nyquist / Double(model.bands)))
        var visible = 0
        var peak = -Float.infinity
        for column in 0 ..< model.columns {
            let value = model.value(column: column, band: band)
            peak = max(peak, value)
            if value > -90 { visible += 1 }
        }
        line("    \(reduction.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) peak \(String(format: "%8.2f", peak)) dBFS · visible in \(visible)/\(model.columns) columns")
    }

    line("\n  an abrupt cutoff at 16 kHz over 60 s of noise")
    let filtered = Signal.lowPassed(Signal.noise(1 << 20, amplitude: 0.5), cutoff: 16_000, sampleRate: sampleRate)
    for reduction in [Reduction.maximum, .mean] {
        guard let model = spectrogram(channels: [filtered], sampleRate: sampleRate, reduction: reduction),
              let below = model.peak(atFrequency: 15_000), let above = model.peak(atFrequency: 17_000) else { continue }
        line("    \(reduction.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) 15 kHz \(String(format: "%7.2f", below)) · 17 kHz \(String(format: "%7.2f", above)) · step \(String(format: "%5.1f", below - above)) dB · edge \(String(format: "%.0f", model.highestFrequency(above: -90) ?? 0)) Hz")
        ledger.check("a 16 kHz cutoff is a cliff under \(reduction.rawValue) reduction", below - above > 50,
                     detail: "\(String(format: "%.1f", below - above)) dB step")
    }

    line("\n  RISK: does the maximum turn one isolated click into a surface?")
    var sparse = Signal.silence(count)
    for (offset, value) in Signal.noise(2_048, amplitude: 0.5, seed: 7).enumerated() {
        sparse[count / 3 + offset] = value
    }
    var loudColumns: [Reduction: Int] = [:]
    for reduction in [Reduction.maximum, .mean] {
        guard let model = spectrogram(channels: [sparse], sampleRate: sampleRate, reduction: reduction) else { continue }
        var columns = 0
        for column in 0 ..< model.columns {
            var peak = -Float.infinity
            for band in 0 ..< model.bands { peak = max(peak, model.value(column: column, band: band)) }
            if peak > -90 { columns += 1 }
        }
        loudColumns[reduction] = columns
        line("    \(reduction.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(columns)/\(model.columns) columns above -90 dBFS")
    }
    if let maximum = loudColumns[.maximum], let mean = loudColumns[.mean] {
        ledger.check("the maximum does not spread an isolated click across the file", maximum <= mean + 1,
                     detail: "\(maximum) columns against the mean's \(mean)")
        line("    The risk is real but bounded here. A file with dense impulsive noise would light more")
        line("    columns under either strategy; that is recorded rather than hidden.")
    }
}
