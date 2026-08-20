import Foundation

import AudioInspectorDomain

/// Turns raw values into something a person reads, and nothing more.
///
/// Two rules govern everything here:
///
/// - **A summary never hides the datum.** Every rounded form has an exact counterpart (`…Exact`) that
///   the report shows as secondary detail, so `44.1 kHz` always has `44,100 Hz` behind it.
/// - **Nothing is characterised.** These produce names and magnitudes, never judgements: no value is
///   described as high, low, better or worse.
///
/// Formatting is pinned to a **fixed locale on purpose**. These strings are asserted by the test suite,
/// and a machine's region must not change whether it passes; the package declares `en` as its only
/// localization, so there is no user-facing locale to honour yet.
enum HumanFormat {
    /// Fixed so results never depend on the machine running them. `en_US` rather than `en_US_POSIX`:
    /// POSIX is the invariant locale meant for serialization and omits grouping separators, which is
    /// exactly wrong for reading — `44,100` is easier than `44100`.
    static let locale = Locale(identifier: "en_US")

    // MARK: - Counts and sizes

    /// `8421376` → `8.4 MB`.
    static func byteCount(_ bytes: Int) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }

    /// `8421376` → `8,421,376 bytes` — the exact figure behind the rounded one.
    static func byteCountExact(_ bytes: Int) -> String {
        "\(bytes.formatted(.number.locale(locale))) bytes"
    }

    // MARK: - Time

    /// `372.51` → `6:13` (rounded to the nearest second; the exact value is kept as detail); an hour or
    /// more → `1:02:03`. Non-finite or negative input yields `nil` rather than a fabricated duration.
    static func duration(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let value = Duration.seconds(seconds)
        return seconds >= 3_600
            ? value.formatted(.time(pattern: .hourMinuteSecond).locale(locale))
            : value.formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// `372.51` → `372.51 seconds`.
    static func durationExact(_ seconds: Double) -> String {
        "\(seconds.formatted(.number.precision(.fractionLength(0 ... 3)).locale(locale))) seconds"
    }

    /// A date and time at a fixed, readable width.
    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
    }

    // MARK: - Rates

    /// `44100` → `44.1 kHz`; `48000` → `48 kHz`.
    static func sampleRate(_ hertz: Int) -> String {
        "\(scaled(hertz, by: 1_000)) kHz"
    }

    /// `44100` → `44,100 Hz`.
    static func sampleRateExact(_ hertz: Int) -> String {
        "\(hertz.formatted(.number.locale(locale))) Hz"
    }

    /// `128000` → `128 kbps`; `1411200` → `1,411.2 kbps`. Audio bitrates are read in kbps at every
    /// scale, including lossless, so no megabit form is introduced.
    static func bitrate(_ bitsPerSecond: Int) -> String {
        "\(scaled(bitsPerSecond, by: 1_000)) kbps"
    }

    /// `128000` → `128,000 bit/s`.
    static func bitrateExact(_ bitsPerSecond: Int) -> String {
        "\(bitsPerSecond.formatted(.number.locale(locale))) bit/s"
    }

    // MARK: - Audio shape

    /// `1` → `Mono`, `2` → `Stereo`, anything else → `6 channels`.
    ///
    /// The domain knows a **count**, not a layout. Naming six channels `5.1` would assert a
    /// configuration that was never read, so above two only the number is given.
    static func channels(_ count: Int) -> String {
        switch count {
        case 1: "Mono"
        case 2: "Stereo"
        default: "\(count.formatted(.number.locale(locale))) channels"
        }
    }

    /// `1` → `1 channel`; `2` → `2 channels` — the count behind the name.
    static func channelsExact(_ count: Int) -> String {
        "\(count.formatted(.number.locale(locale))) channel\(count == 1 ? "" : "s")"
    }

    /// `16` → `16-bit`.
    static func bitDepth(_ bits: Int) -> String {
        "\(bits.formatted(.number.locale(locale)))-bit"
    }

    /// A frequency on an axis: `0` → `0 Hz`; `2000` → `2 kHz`; `22050` → `22.05 kHz`.
    ///
    /// Below a kilohertz the value is given in Hz, because `0.5 kHz` reads worse than `500 Hz` and the
    /// bottom of a frequency axis is where small numbers live. Two decimals for the same reason
    /// `sampleRate` uses them: at one, `22050 Hz` would round to `22 kHz` and misstate the top of the
    /// axis a reader checks the file's rate against.
    static func frequency(_ hertz: Double) -> String {
        guard hertz.isFinite, hertz >= 0 else { return "—" }
        guard hertz >= 1_000 else {
            return "\(hertz.formatted(.number.precision(.fractionLength(0 ... 0)).locale(locale))) Hz"
        }
        let kilohertz = (hertz / 1_000)
            .formatted(.number.precision(.fractionLength(0 ... 2)).locale(locale))
        return "\(kilohertz) kHz"
    }

    // MARK: - Signal level

    /// A linear amplitude on the domain's own normalized scale, as dBFS: `1.0` → `0.00 dBFS`,
    /// `0.5` → `-6.02 dBFS`. A sample genuinely beyond full scale reads **positive**, explicitly signed,
    /// rather than being hidden — the domain keeps such a sample exactly as read (`PCMChunk`'s own
    /// contract), and a presentation that clamped it would misstate a real fact about the file.
    ///
    /// Exact silence floors at `Spectrogram.floorDecibels` (−120 dBFS), reusing that convention rather
    /// than inventing a second one, and specifically to avoid `log10(0)`'s mathematical `-∞` — never
    /// shown as such (task 5.1's own "positive value ... explained rather than hidden" cuts the other
    /// way too: a meaningless infinity must not be shown as though it were a measurement).
    static func decibelsFullScale(_ linearAmplitude: Float) -> String {
        let magnitude = Double(abs(linearAmplitude))
        let decibels = magnitude > 0 ? 20 * log10(magnitude) : -Double.infinity
        let floored = max(Double(Spectrogram.floorDecibels), decibels)
        let formatted = floored.formatted(
            .number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)).locale(locale)
        )
        return "\(formatted) dBFS"
    }

    /// A linear amplitude as **dBTP** — the unit a true peak is quoted in, and deliberately not the unit
    /// beside it.
    ///
    /// The arithmetic is identical to `decibelsFullScale`, and the unit is not: dBFS describes the
    /// largest **stored sample**, dBTP an estimate of the reconstructed waveform **between** samples.
    /// They are normally different numbers produced by different methods, so showing one of them under
    /// the other's unit would quietly claim a measurement that was never made. The two formatters stay
    /// separate for that reason alone — not because the maths differs.
    ///
    /// Reference points, pinned by test: `1.0` → `0.00 dBTP`, `0.5` → `-6.02 dBTP`, `1.1` → `+0.83 dBTP`
    /// (**explicitly signed and never clamped** — a reconstruction that genuinely exceeds full scale is
    /// the fact this measurement exists to reveal), and exact silence floors at the project's own
    /// `Spectrogram.floorDecibels` rather than showing `log10(0)`'s `-∞`.
    ///
    /// **A value this formatter cannot be given is `nil`.** "Not computable" is the caller's word for a
    /// channel that carried no samples, and it never arrives here as a fabricated zero.
    static func decibelsTruePeak(_ linearAmplitude: Float) -> String {
        let magnitude = Double(abs(linearAmplitude))
        let decibels = magnitude > 0 ? 20 * log10(magnitude) : -Double.infinity
        let floored = max(Double(Spectrogram.floorDecibels), decibels)
        let formatted = floored.formatted(
            .number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)).locale(locale)
        )
        return "\(formatted) dBTP"
    }

    /// A programme's **integrated loudness**, in `LUFS`: `-23.04` → `-23.0 LUFS`, `0` → `0.0 LUFS`,
    /// `2.14` → `+2.1 LUFS`.
    ///
    /// Three things separate it from the two formatters above, and each is deliberate:
    ///
    /// - **It converts nothing.** dBFS and dBTP turn a linear amplitude into decibels here; LUFS is
    ///   already the quantity the domain stores (`LoudnessMeasurement`'s own contract, ADR-0022 §5), so
    ///   this only renders it. There is no `log10` to reach an infinity through, which is why there is
    ///   no floor.
    /// - **One decimal**, not two. It is the display precision EBU Tech 3341 §2.8 states for a meter
    ///   reading, and the accumulator's own agreement with an independent implementation is pinned at
    ///   ±0.1 — a second decimal would assert a resolution the measurement is not qualified to.
    /// - **Nothing is clamped, floored or substituted.** A programme genuinely above full scale reads
    ///   positive, explicitly signed, exactly as a true peak above unity does. The standard's −70 LKFS
    ///   absolute gate is a threshold on *blocks*, never a floor on the result, and a value that could
    ///   not be produced never reaches this function — absence is said in words by the caller.
    ///
    /// The sign strategy is the one `decibelsFullScale`/`decibelsTruePeak` already use, so a positive
    /// reading is never mistaken for a negative one and zero is not given a decorative `+`.
    static func loudnessFullScale(_ lufs: Double) -> String {
        let formatted = lufs.formatted(
            .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)).locale(locale)
        )
        return "\(formatted) LUFS"
    }

    /// A linear, signed value with no unit — DC offset has no good behaviour on a decibel scale, since
    /// it can be negative and sits naturally near zero. Four decimal places: `Float`'s own roughly seven
    /// significant digits give a comfortable margin at this magnitude, and four places already resolve
    /// an offset two orders below what real capture equipment introduces without asserting more
    /// precision than the type honestly carries.
    static func linearOffset(_ value: Float) -> String {
        Double(value).formatted(
            .number.precision(.fractionLength(4)).sign(strategy: .always(includingZero: false)).locale(locale)
        )
    }

    // MARK: - Programme bandwidth

    /// A programme bandwidth reading, rounded so that **no digit claims a distinction the analysis
    /// cannot make**.
    ///
    /// The measurement carries a frequency and the bin width that produced it, and the bin width is the
    /// quantisation of the value — *not* an uncertainty (ADR-0023). So this does not print a `±`; it
    /// simply refuses to show a digit finer than the bin. The displayed value is rounded to the
    /// smallest power of ten that is **at least** the resolution, and the number of decimals follows
    /// from that step, so the last digit shown is always worth more than one bin.
    ///
    /// Worked: at every supported rate the window is fixed in *time*, so the resolution is about 23 Hz
    /// whether the file is 44.1 or 192 kHz. The step is therefore 100 Hz and the form is one decimal in
    /// kilohertz at all five rates — `16 101.5625 Hz` reads `16.1 kHz`, and `20 015.625 Hz` reads
    /// `20 kHz` rather than `20.02 kHz`, which would imply a 10 Hz distinction the bins do not support.
    ///
    /// Decimals are capped at two, matching the vocabulary the rest of the report already uses. The cap
    /// can only ever show *less* precision than the resolution allows, which is the safe direction; the
    /// rule is one-sided by design, and no input makes it show more.
    static func programmeBandwidth(_ hertz: Double, resolution: Double) -> String {
        guard hertz.isFinite, hertz >= 0, resolution.isFinite, resolution > 0 else { return "—" }
        let exponent = Int(ceil(log10(resolution)))
        let step = pow(10.0, Double(exponent))
        let rounded = (hertz / step).rounded() * step
        guard rounded >= 1_000 else {
            return "\(rounded.formatted(.number.precision(.fractionLength(0 ... 0)).locale(locale))) Hz"
        }
        let decimals = min(2, max(0, 3 - exponent))
        let kilohertz = (rounded / 1_000)
            .formatted(.number.precision(.fractionLength(0 ... decimals)).locale(locale))
        return "\(kilohertz) kHz"
    }

    // MARK: - Shared

    /// Divides and drops trailing zeros, so `48000/1000` reads `48` and `44100/1000` reads `44.1`.
    ///
    /// Two decimals rather than one: at one decimal, `22050 Hz` rounds to `22 kHz`, which reads as a
    /// different rate. The exact figure is always shown beside it, but the readable form should not
    /// misstate the value in the first place.
    private static func scaled(_ value: Int, by divisor: Int) -> String {
        (Double(value) / Double(divisor))
            .formatted(.number.precision(.fractionLength(0 ... 2)).locale(locale))
    }
}
