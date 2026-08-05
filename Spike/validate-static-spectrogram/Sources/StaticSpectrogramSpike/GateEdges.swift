import Foundation

/// Gate E — the edges: degenerate inputs, chunking, determinism and cancellation.
@MainActor
func gateEdges() async {
    heading("GATE E — edges and limits")
    let sampleRate = 44_100.0
    let spec = SpectrogramSpec()

    line("\n  a file shorter than one FFT window (1000 samples, window 2048)")
    if let model = spectrogram(channels: [Signal.sine(1_000, frequency: 1_000, sampleRate: sampleRate, amplitude: 0.5)],
                               sampleRate: sampleRate) {
        ledger.check("too-short input yields a model at the floor rather than a fabricated one",
                     model.values.allSatisfy { $0 == spec.floorDB },
                     detail: "\(model.columns)×\(model.bands), all floor")
    }

    line("\n  why the final incomplete frame is discarded rather than zero-padded")
    // Padding is not a strategy the accumulator offers; the number below is measured by padding by hand
    // so the decision is recorded with its cost rather than asserted.
    var padded = Signal.sine(1_000, frequency: 232 * (sampleRate / 2_048), sampleRate: sampleRate, amplitude: 0.5)
    padded.append(contentsOf: Signal.silence(2_048 - padded.count))
    if let model = spectrogram(channels: [padded], sampleRate: sampleRate) {
        let measured = model.loudest().db
        line("    a 0.5 tone padded with silence to fill one window reads \(String(format: "%.2f", measured)) dBFS, not -6.02")
        ledger.check("padding would understate the level, so it is not done", measured < -10,
                     detail: "\(String(format: "%.2f", measured)) dBFS")
        line("    At most fftSize-1 frames — 46 ms at 44.1 kHz — are left undrawn. That is preferred to")
        line("    inventing samples the file does not contain.")
    }

    line("\n  zero-length input")
    if let model = spectrogram(channels: [[Float]()], sampleRate: sampleRate) {
        ledger.check("a zero-length file produces a model entirely at the floor",
                     model.values.allSatisfy { $0 == spec.floorDB }, detail: "\(model.columns)×\(model.bands)")
        line("    NOTE for the contract: this returns a floor-filled model, not an absence. The domain")
        line("    type should decide whether zero frames means an empty model or no model at all, the")
        line("    way WaveformEnvelope did.")
    }

    line("\n  configurations no file can have")
    ledger.check("sample rate 0 is refused",
                 SpectrogramAccumulator(sampleRate: 0, channelCount: 1, totalFrames: 1_000) == nil)
    ledger.check("zero channels is refused",
                 SpectrogramAccumulator(sampleRate: sampleRate, channelCount: 0, totalFrames: 1_000) == nil)
    ledger.check("a negative frame count is refused",
                 SpectrogramAccumulator(sampleRate: sampleRate, channelCount: -1, totalFrames: 1_000) == nil)
    ledger.check("a negative total frame count is refused",
                 SpectrogramAccumulator(sampleRate: sampleRate, channelCount: 1, totalFrames: -1) == nil)

    line("\n  non-finite samples")
    let count = 8 * 2_048
    var withNaN = Signal.sine(count, frequency: 5_000, sampleRate: sampleRate, amplitude: 0.5)
    withNaN[count / 2] = .nan
    let clean = spectrogram(channels: [Signal.sine(count, frequency: 5_000, sampleRate: sampleRate, amplitude: 0.5)],
                            sampleRate: sampleRate)
    if let model = spectrogram(channels: [withNaN], sampleRate: sampleRate), let clean {
        let contaminated = model.values.contains { !$0.isFinite }
        var floored = 0
        for index in 0 ..< model.values.count where model.values[index] == spec.floorDB && clean.values[index] != spec.floorDB {
            floored += 1
        }
        line("    a single NaN sample → model contains non-finite values: \(contaminated)")
        line("    cells that fell to the floor and would not have otherwise: \(floored)")
        ledger.check("a NaN does not leak a non-finite value into the model", !contaminated)
        line("    OBSERVATION for the contract, and it is the uncomfortable one: the NaN does not survive")
        line("    into the model — the clamp absorbs it — but the frames it touched collapse to the floor")
        line("    **silently**, so a corrupted region reads as an absence of energy rather than as a")
        line("    problem. The DOMAIN must therefore reject non-finite samples at the boundary, exactly")
        line("    as WaveformBucket already does, instead of relying on this clamp.")
    }

    line("\n  unusual sample rates")
    for rate in [22_050.0, 8_000.0] {
        guard let model = spectrogram(channels: [Signal.sine(Int(rate), frequency: rate / 4, sampleRate: rate, amplitude: 0.5)],
                                      sampleRate: rate) else { continue }
        let loudest = model.loudest()
        let measured = model.frequency(ofBand: loudest.band)
        ledger.check("\(Int(rate)) Hz maps frequencies correctly",
                     abs(measured - rate / 4) < model.nyquist / Double(model.bands) * 2,
                     detail: "peak at \(String(format: "%.0f", measured)) Hz, expected \(String(format: "%.0f", rate / 4))")
    }

    line("\n  independence from how the caller chunks the file")
    let signal = Signal.sum(
        Signal.sine(1 << 17, frequency: 1_000, sampleRate: sampleRate, amplitude: 0.5),
        Signal.noise(1 << 17, amplitude: 0.01)
    )
    guard let reference = spectrogram(channels: [signal], sampleRate: sampleRate) else { return }
    for chunk in [1, 512, 1_024, 4_096, 65_536] {
        guard let model = spectrogram(channels: [signal], sampleRate: sampleRate, chunk: chunk) else { continue }
        ledger.check("chunk of \(chunk) frames yields an identical model", model.values == reference.values)
    }

    line("\n  determinism")
    let first = spectrogram(channels: [signal], sampleRate: sampleRate)
    let second = spectrogram(channels: [signal], sampleRate: sampleRate)
    ledger.check("the same input twice produces the same model", first?.values == second?.values)

    line("\n  cancellation")
    let long = Signal.sine(Int(sampleRate * 60), frequency: 1_000, sampleRate: sampleRate, amplitude: 0.5)
    let task = Task { await makeSpectrogram(channels: [long], sampleRate: sampleRate, chunk: 4_096) }
    task.cancel()
    let cancelled = await task.value
    ledger.check("a cancelled run yields no model at all", cancelled == nil,
                 detail: cancelled == nil ? "nil — nothing partial presented as complete" : "a model was produced")
}
