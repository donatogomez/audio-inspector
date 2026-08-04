import Foundation

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
