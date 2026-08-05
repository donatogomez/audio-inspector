import Foundation

/// Gate B — can the reduced model tell one band cutoff from another?
///
/// This is the gate that decides whether the whole slice is worth building: a collector looking at a
/// "lossless" file wants to see where its content stops. If 1024×512 cannot separate 18 from 19 kHz,
/// the reduction is wrong and the contract must not be written around it.
@MainActor
func gateCutoff() {
    heading("GATE B — cutoff discrimination")
    let cutoffs = [16_000.0, 18_000.0, 19_000.0, 20_000.0, 22_000.0]
    let sampleCount = 1 << 18

    for sampleRate in [44_100.0, 48_000.0, 96_000.0, 192_000.0] {
        let nyquist = sampleRate / 2
        let bandHz = nyquist / 512
        line("\n  \(Int(sampleRate)) Hz — Nyquist \(String(format: "%.1f", nyquist / 1_000)) kHz, reduced band \(String(format: "%.1f", bandHz)) Hz")

        let noise = Signal.noise(sampleCount, amplitude: 0.5)
        var observed: [(cutoff: Double, edge: Double)] = []
        for cutoff in cutoffs where cutoff < nyquist {
            let filtered = Signal.lowPassed(noise, cutoff: cutoff, sampleRate: sampleRate)
            guard let model = spectrogram(channels: [filtered], sampleRate: sampleRate),
                  let edge = model.highestFrequency(above: -90) else { continue }
            observed.append((cutoff, edge))
            line("    cutoff \(String(format: "%5.0f", cutoff)) Hz → highest band above -90 dBFS \(String(format: "%8.0f", edge)) Hz  (error \(String(format: "%+5.0f", edge - cutoff)) Hz)")
        }

        if let model = spectrogram(channels: [noise], sampleRate: sampleRate),
           let edge = model.highestFrequency(above: -90) {
            line("    no cutoff        → highest band above -90 dBFS \(String(format: "%8.0f", edge)) Hz  (Nyquist \(String(format: "%.0f", nyquist)) Hz)")
            ledger.check("unfiltered content reaches Nyquist at \(Int(sampleRate)) Hz", edge > nyquist * 0.99,
                         detail: "\(String(format: "%.0f", edge)) Hz")
        }

        for index in 1 ..< observed.count {
            let separation = observed[index].edge - observed[index - 1].edge
            let bands = separation / bandHz
            ledger.check("\(Int(observed[index - 1].cutoff / 1_000)) kHz is separable from \(Int(observed[index].cutoff / 1_000)) kHz at \(Int(sampleRate)) Hz",
                         bands >= 2,
                         detail: "\(String(format: "%.0f", separation)) Hz = \(String(format: "%.1f", bands)) reduced bands")
        }
    }

    line("\n  The error grows with the sample rate because a reduced band covers more hertz.")
    line("  It is an uncertainty on the observed edge, and the report states it as such.")
}
