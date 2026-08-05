/// A whole file's spectral energy: a fixed grid of columns over time and bands over frequency, in
/// absolute dBFS.
///
/// The type is intentionally poor. It carries no view size, no colour, no normalisation factor, no
/// URL, no container and no codec, because none of those describe the audio — and a
/// resolution-independent model is what lets a view be resized without decoding or transforming the
/// file again.
///
/// It is not `Codable`: the spectrogram never enters the `schemaVersion` 1 export and is not persisted
/// (ADR-0009). Conforming it would advertise a contract that does not exist.
///
/// ## The scale is absolute, and has a floor but no ceiling
///
/// Values are dBFS referenced to full scale, never normalised per file: the user compares copies of the
/// same music, and scaling each file to its own peak would make two files incomparable.
///
/// `floorDecibels` is a genuine invariant — everything quieter is represented *as* the floor, so no
/// value below it exists. There is deliberately **no upper bound**. A file whose samples exceed full
/// scale produces values above 0 dBFS, and those are real; the spike measured a sample at 1.5 reading
/// +3.52 dBFS. Limiting them belongs to drawing, which has edges, not to the data, which does not —
/// exactly as `WaveformBucket` keeps samples beyond `-1...1`. The −120…0 range the interface shows is a
/// property of the legend, not of this type.
///
/// ## It describes energy, and concludes nothing
///
/// Where energy stops is observable here. *Why* it stops is not: a cutoff is compatible with lossy
/// encoding, with the master, and with deliberate filtering. Nothing in this type — no field, no
/// derived value, no name — may be read as a verdict about a file's origin or quality.
public struct Spectrogram: Sendable, Equatable {
    /// Everything quieter than this is represented as this. Measured against real content rather than
    /// chosen: the spike observed the empty region above a lossy cutoff sitting near −118 dBFS, so this
    /// floor discards nothing a file is likely to contain.
    public static let floorDecibels: Float = -120

    /// dBFS in row-major order: `column * bandCount + band`.
    public let values: [Float]
    /// Columns of time, oldest first. **Zero is valid**, and is what a file with no audio produces.
    public let columnCount: Int
    /// Bands of frequency, lowest first, linear from 0 Hz to `nyquist`.
    public let bandCount: Int
    /// The stream this was derived from. Present because a band index means nothing without it.
    public let sampleRate: Double
    /// Total frames the analysis covered.
    public let frameCount: Int
    /// How many channels were combined into each value. Present because "the maximum across all
    /// channels" is not a complete statement without it.
    public let channelCount: Int

    /// Fails when the parts do not describe a possible analysis.
    ///
    /// The empty case is **valid, not an error**: a file with no audio yields no columns. That is a
    /// spectrogram of nothing, and it is a different thing from *no spectrogram was produced* — which
    /// is an absence expressed by the port — and different again from *producing one failed*, which is
    /// a thrown error. Keeping the three apart is why this model carries no notion of availability, and
    /// it is the same distinction `WaveformEnvelope` draws.
    public init?(
        values: [Float],
        columnCount: Int,
        bandCount: Int,
        sampleRate: Double,
        frameCount: Int,
        channelCount: Int
    ) {
        guard columnCount >= 0, columnCount <= SpectrogramGridMapping.defaultMaximumColumnCount else { return nil }
        guard bandCount >= 0, bandCount <= SpectrogramGridMapping.defaultMaximumBandCount else { return nil }
        guard sampleRate.isFinite, sampleRate > 0 else { return nil }
        guard frameCount >= 0, channelCount >= 1 else { return nil }
        guard values.count == columnCount * bandCount else { return nil }
        // Finite and at or above the floor. A value below it would mean the producer skipped the floor
        // it is required to apply, and a non-finite one would mean a sample slipped past the boundary
        // that exists to refuse it.
        guard values.allSatisfy({ $0.isFinite && $0 >= Self.floorDecibels }) else { return nil }
        // A file with no audio has no columns; columns without frames would describe audio that is not
        // there.
        guard (frameCount == 0) == (columnCount == 0) else { return nil }

        self.values = values
        self.columnCount = columnCount
        self.bandCount = bandCount
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        self.channelCount = channelCount
    }

    /// The spectrogram of a file that holds no audio.
    public static func empty(sampleRate: Double, channelCount: Int) -> Spectrogram? {
        Spectrogram(
            values: [], columnCount: 0, bandCount: 0,
            sampleRate: sampleRate, frameCount: 0, channelCount: channelCount
        )
    }

    /// The highest frequency represented. The whole of it is meaningful: an empty upper range in a file
    /// that declares a high sample rate is itself something to see, so nothing here crops it.
    public var nyquist: Double { sampleRate / 2 }

    /// The dBFS at one cell, or `nil` outside the grid.
    public func value(column: Int, band: Int) -> Float? {
        guard column >= 0, column < columnCount, band >= 0, band < bandCount else { return nil }
        return values[column * bandCount + band]
    }

    /// The centre frequency of a band. Linear: band `b` of `n` spans `b/n … (b+1)/n` of Nyquist.
    public func frequency(ofBand band: Int) -> Double? {
        guard band >= 0, band < bandCount else { return nil }
        return (Double(band) + 0.5) * nyquist / Double(bandCount)
    }
}
