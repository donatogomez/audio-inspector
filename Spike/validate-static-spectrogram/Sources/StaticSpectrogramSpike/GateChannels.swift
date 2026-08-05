import Foundation

/// Gate D — how several channels become one picture.
///
/// This gate contains a **negative control**: the strategy that was proposed first, combining samples
/// in the time domain, is run here so its failure is reproducible rather than asserted. It is not an
/// alternative the product may choose — it is kept because "we tried it and this is what it did" is
/// worth more to a later reader than "we decided not to".
@MainActor
func gateChannels() {
    heading("GATE D — channel combination")
    let sampleRate = 44_100.0
    let count = 8 * 2_048
    let binHz = sampleRate / 2_048
    let lowTone = 232 * binHz   // ~4996 Hz
    let highTone = 464 * binHz  // ~9991 Hz

    let left = Signal.sine(count, frequency: lowTone, sampleRate: sampleRate, amplitude: 0.5)
    let right = Signal.sine(count, frequency: highTone, sampleRate: sampleRate, amplitude: 0.5)
    let silence = Signal.silence(count)

    // MARK: The negative control — combining in the time domain

    line("\n  NEGATIVE CONTROL — maximum taken over samples, in the time domain")
    line("  Two channels carrying DIFFERENT pure tones, both at 0.5 (each should read -6.02 dBFS).")

    var timeDomain = [Float](repeating: 0, count: count)
    for index in 0 ..< count {
        // Take the sample of whichever channel is louder, keeping its sign.
        timeDomain[index] = abs(left[index]) >= abs(right[index]) ? left[index] : right[index]
    }
    if let model = spectrogram(channels: [timeDomain], sampleRate: sampleRate) {
        let low = model.peak(atFrequency: lowTone) ?? -.infinity
        let high = model.peak(atFrequency: highTone) ?? -.infinity
        let (spurious, worst) = spuriousBands(in: model, excluding: [lowTone, highTone], above: -80)
        line("    peaks: \(String(format: "%.2f", low)) dBFS @ 5 kHz · \(String(format: "%.2f", high)) dBFS @ 10 kHz")
        line("    spurious bands above -80 dBFS: \(spurious), worst \(worst == -Float.infinity ? "none" : String(format: "%.2f", worst) + " dBFS")")
        ledger.check("the time-domain control does invent spectral content (this is the failure being recorded)",
                     spurious > 0,
                     detail: "\(spurious) bands that exist in neither channel")
        line("    → A signal that is in neither channel would be drawn as if it were in the file.")
        line("      For an instrument whose job is to show where energy stops, that is disqualifying:")
        line("      invented energy high up could hide a real cutoff. NOT a valid strategy.")
    }

    // MARK: The approved strategy — combining in the frequency domain

    line("\n  APPROVED — one STFT per channel, maximum of magnitudes per bin")
    if let model = spectrogram(channels: [left, right], sampleRate: sampleRate) {
        let low = model.peak(atFrequency: lowTone) ?? -.infinity
        let high = model.peak(atFrequency: highTone) ?? -.infinity
        let (spurious, _) = spuriousBands(in: model, excluding: [lowTone, highTone], above: -80)
        line("    peaks: \(String(format: "%.2f", low)) dBFS @ 5 kHz · \(String(format: "%.2f", high)) dBFS @ 10 kHz")
        ledger.check("both tones read their true level", abs(low + 6.02) < 0.05 && abs(high + 6.02) < 0.05,
                     detail: "\(String(format: "%.2f", low)) and \(String(format: "%.2f", high)) dBFS")
        ledger.check("nothing spurious is invented", spurious == 0, detail: "\(spurious) spurious bands")
    }

    line("\n  the invariants")
    let mono = spectrogram(channels: [left], sampleRate: sampleRate)
    let stereoIdentical = spectrogram(channels: [left, left], sampleRate: sampleRate)
    let leftOnly = spectrogram(channels: [left, silence], sampleRate: sampleRate)
    let rightOnly = spectrogram(channels: [silence, left], sampleRate: sampleRate)
    let opposite = spectrogram(channels: [left, left.map { -$0 }], sampleRate: sampleRate)

    if let mono, let stereoIdentical, let leftOnly, let rightOnly, let opposite {
        ledger.check("a tone in the left channel alone survives", leftOnly.values == mono.values)
        ledger.check("left-only and right-only are indistinguishable", leftOnly.values == rightOnly.values)
        ledger.check("identical channels read as one", stereoIdentical.values == mono.values)
        ledger.check("opposite polarity does not cancel", opposite.values == mono.values,
                     detail: "peak \(String(format: "%.2f", opposite.loudest().db)) dBFS")

        let quiet = spectrogram(channels: [Signal.sine(count, frequency: lowTone, sampleRate: sampleRate, amplitude: 0.05), silence],
                                sampleRate: sampleRate)
        if let quiet {
            let difference = leftOnly.loudest().db - quiet.loudest().db
            ledger.check("no normalisation across channel layouts", abs(difference - 20) < 0.05,
                         detail: "\(String(format: "%.2f", difference)) dB apart, expected 20.00")
        }
    }

    line("\n  cost of the approved strategy — one transform per channel, run sequentially")
    let monoStart = Date()
    _ = spectrogram(channels: [left], sampleRate: sampleRate)
    let monoMs = Date().timeIntervalSince(monoStart) * 1_000
    let stereoStart = Date()
    _ = spectrogram(channels: [left, right], sampleRate: sampleRate)
    let stereoMs = Date().timeIntervalSince(stereoStart) * 1_000
    line("    mono \(String(format: "%.1f", monoMs)) ms · stereo \(String(format: "%.1f", stereoMs)) ms → \(String(format: "%.1f", stereoMs / max(monoMs, 0.001)))×")
    line("    Accepted knowingly. No promise is made about timings for more than two channels.")
}

/// Bands carrying energy above `threshold` that no expected tone accounts for.
private func spuriousBands(in model: SpectrogramModel, excluding frequencies: [Double], above threshold: Float) -> (count: Int, worst: Float) {
    let bandWidth = model.nyquist / Double(model.bands)
    let excluded = Set(frequencies.flatMap { frequency -> [Int] in
        let band = Int(frequency / bandWidth)
        return [band - 1, band, band + 1]
    })
    var count = 0
    var worst = -Float.infinity
    for band in 0 ..< model.bands where !excluded.contains(band) {
        for column in 0 ..< model.columns {
            let value = model.value(column: column, band: band)
            if value > threshold {
                count += 1
                worst = max(worst, value)
                break
            }
        }
    }
    return (count, worst)
}
