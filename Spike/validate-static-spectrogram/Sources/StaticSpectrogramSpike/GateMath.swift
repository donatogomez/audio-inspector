import Foundation

/// Gate A — the elementary maths, on synthetic signals only. No file, no FFmpeg.
///
/// What is being established: the scale is exact, the floor behaves, nothing is clamped and nothing is
/// normalised. If any of this were wrong every later gate would be measuring the wrong thing.
@MainActor
func gateMath() {
    heading("GATE A — elementary maths")
    let sampleRate = 44_100.0
    let spec = SpectrogramSpec()
    let count = 8 * spec.fftSize
    let binHz = sampleRate / Double(spec.fftSize)
    line("  FFT \(spec.fftSize) · hop \(spec.hop) · bin \(String(format: "%.2f", binHz)) Hz · floor \(spec.floorDB) dBFS · model \(spec.maxColumns)×\(spec.maxBands)")

    line("\n  silence")
    if let model = spectrogram(channels: [Signal.silence(count)], sampleRate: sampleRate) {
        ledger.check("silence sits exactly on the floor", model.values.allSatisfy { $0 == spec.floorDB },
                     detail: "max \(model.values.max() ?? 0) dBFS")
    }

    line("\n  DC")
    if let model = spectrogram(channels: [Signal.dc(count, level: 0.5)], sampleRate: sampleRate) {
        let loudest = model.loudest()
        ledger.check("DC is preserved in the lowest band", loudest.band == 0,
                     detail: "band \(loudest.band), \(String(format: "%.2f", loudest.db)) dBFS")
    }

    line("\n  tone centred exactly on a bin (bin 232 = \(String(format: "%.2f", 232 * binHz)) Hz)")
    for amplitude in [Float(1.0), 0.5, 0.1] {
        let tone = Signal.sine(count, frequency: 232 * binHz, sampleRate: sampleRate, amplitude: amplitude)
        guard let model = spectrogram(channels: [tone], sampleRate: sampleRate) else { continue }
        let measured = model.loudest().db
        let expected = 20 * log10(amplitude)
        ledger.check("amplitude \(amplitude) reads \(String(format: "%+.2f", expected)) dBFS",
                     abs(measured - expected) < 0.01,
                     detail: "measured \(String(format: "%+.2f", measured)), error \(String(format: "%+.3f", measured - expected)) dB")
    }

    line("\n  tone exactly between two bins (bin 232.5) — scalloping loss")
    if let model = spectrogram(channels: [Signal.sine(count, frequency: 232.5 * binHz, sampleRate: sampleRate, amplitude: 0.5)],
                               sampleRate: sampleRate) {
        let measured = model.loudest().db
        let expected: Float = 20 * log10(0.5)
        let loss = expected - measured
        line("    worst-case scalloping loss: \(String(format: "%.2f", loss)) dB (Hann's theoretical maximum is 1.42 dB)")
        ledger.check("scalloping loss stays within Hann's theoretical maximum", loss <= 1.45,
                     detail: "\(String(format: "%.2f", loss)) dB")
    }

    line("\n  two tones (1 kHz @ 0.5, 10 kHz @ 0.05)")
    let twoTones = Signal.sum(
        Signal.sine(count, frequency: 1_000, sampleRate: sampleRate, amplitude: 0.5),
        Signal.sine(count, frequency: 10_000, sampleRate: sampleRate, amplitude: 0.05)
    )
    if let model = spectrogram(channels: [twoTones], sampleRate: sampleRate) {
        let low = model.peak(atFrequency: 1_000) ?? -.infinity
        let high = model.peak(atFrequency: 10_000) ?? -.infinity
        line("    1 kHz \(String(format: "%.2f", low)) dBFS · 10 kHz \(String(format: "%.2f", high)) dBFS")
        ledger.check("both tones are resolved within scalloping loss",
                     abs(low - 20 * log10(0.5)) < 1.5 && abs(high - 20 * log10(0.05)) < 1.5)
    }

    line("\n  impulse")
    if let model = spectrogram(channels: [Signal.impulse(count, at: count / 2, amplitude: 1.0)], sampleRate: sampleRate) {
        var active = 0
        for band in 0 ..< model.bands where (model.peak(atFrequency: model.frequency(ofBand: band)) ?? -.infinity) > -80 {
            active += 1
        }
        ledger.check("an impulse produces a flat spectrum", active > model.bands * 9 / 10,
                     detail: "\(active)/\(model.bands) bands above -80 dBFS")
    }

    line("\n  finite values beyond [-1, 1]")
    if let model = spectrogram(channels: [Signal.sine(count, frequency: 232 * binHz, sampleRate: sampleRate, amplitude: 1.5)],
                               sampleRate: sampleRate) {
        let measured = model.loudest().db
        ledger.check("a sample above full scale is not clamped", measured > 0,
                     detail: "\(String(format: "%+.2f", measured)) dBFS, expected \(String(format: "%+.2f", 20 * log10(Float(1.5))))")
    }

    line("\n  no normalisation — two files, same tone, 20 dB apart")
    let loud = spectrogram(channels: [Signal.sine(count, frequency: 232 * binHz, sampleRate: sampleRate, amplitude: 0.5)], sampleRate: sampleRate)
    let quiet = spectrogram(channels: [Signal.sine(count, frequency: 232 * binHz, sampleRate: sampleRate, amplitude: 0.05)], sampleRate: sampleRate)
    if let loud, let quiet {
        let difference = loud.loudest().db - quiet.loudest().db
        ledger.check("levels stay comparable between files", abs(difference - 20) < 0.01,
                     detail: "\(String(format: "%.2f", difference)) dB apart, expected 20.00")
    }
}
