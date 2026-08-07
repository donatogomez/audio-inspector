import AudioInspectorDomain
import SwiftUI

/// The colour a level is drawn in, and nothing else.
///
/// ## Intensity, never quality
///
/// The ramp is **strictly increasing in luminance** from the floor to full scale: dark → deep blue →
/// cyan → pale yellow-white. Two consequences follow, and both are the point:
///
/// - It stays readable in greyscale and under colour vision deficiency, because the ordering survives
///   when hue does not. Nothing in the drawing depends on colour alone — the legend states the numbers
///   and the section states the range in words.
/// - **No green-good, no red-bad.** The project's standing rule is that colour never says whether
///   something is good; here it says only *how much energy is present*. Spek's ramp passes through
///   green and red and is deliberately not copied.
///
/// ## It maps the picture, never the data
///
/// The visual range is −120…0 dBFS. Values above 0 dBFS are real — the domain keeps a sample at 1.5
/// reading +3.52 dBFS — and they map to the **top** of the ramp rather than being written back or
/// discarded. The clamp applies to the colour coordinate and only there; `Spectrogram.values` is never
/// modified, and this type has no way to modify it.
enum SpectrogramColourRamp {
    /// The range the ramp spans, which is the range the legend states.
    static let range: ClosedRange<Float> = SpectrogramCopy.legendRange

    /// The ramp's stops, darkest first. Luminance rises strictly from one to the next; the hue shift
    /// from cold to warm is what makes small differences visible, not what carries the meaning.
    ///
    /// Written as literal components so the ramp is deterministic and needs no colour space
    /// negotiation: the same level always produces the same colour, on any display.
    private static let stops: [(position: Double, red: Double, green: Double, blue: Double)] = [
        (0.00, 0.020, 0.020, 0.055), // near-black, the floor
        (0.25, 0.090, 0.130, 0.420), // deep blue
        (0.50, 0.110, 0.450, 0.620), // teal
        (0.75, 0.360, 0.780, 0.700), // cyan-green
        (1.00, 0.980, 0.980, 0.900), // pale yellow-white, full scale
    ]

    /// Where a level sits on the ramp: `0` at the floor or below, `1` at full scale or above.
    ///
    /// A non-finite value cannot come from the domain — `Spectrogram` refuses one — but it is answered
    /// for explicitly rather than left to produce a silent `NaN` coordinate: it is treated as the floor,
    /// which draws it as the quietest thing the ramp can show rather than as an invisible hole.
    static func position(for decibels: Float) -> Double {
        guard decibels.isFinite else { return 0 }
        let clamped = min(max(decibels, range.lowerBound), range.upperBound)
        return Double((clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    /// The colour components a level is drawn in, interpolated between the two stops around it.
    static func components(for decibels: Float) -> (red: Double, green: Double, blue: Double) {
        let position = position(for: decibels)
        guard let upperIndex = stops.firstIndex(where: { $0.position >= position }) else {
            let last = stops[stops.count - 1]
            return (last.red, last.green, last.blue)
        }
        guard upperIndex > 0 else {
            let first = stops[0]
            return (first.red, first.green, first.blue)
        }

        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let span = upper.position - lower.position
        let t = span > 0 ? (position - lower.position) / span : 0
        return (
            red: lower.red + (upper.red - lower.red) * t,
            green: lower.green + (upper.green - lower.green) * t,
            blue: lower.blue + (upper.blue - lower.blue) * t
        )
    }

    static func colour(for decibels: Float) -> Color {
        let components = components(for: decibels)
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    /// Relative luminance, for asserting that the ramp rises monotonically and stays readable without
    /// hue. The Rec. 709 coefficients, applied to the components as drawn.
    static func luminance(for decibels: Float) -> Double {
        let c = components(for: decibels)
        return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
    }

    /// The legend's swatches, darkest first — the same ramp the drawing uses, sampled evenly.
    static func legendStops(count: Int = 32) -> [Color] {
        guard count > 1 else { return [colour(for: range.lowerBound)] }
        return (0 ..< count).map { index in
            let t = Float(index) / Float(count - 1)
            return colour(for: range.lowerBound + t * (range.upperBound - range.lowerBound))
        }
    }

    /// The numbers printed beneath the legend. Without them a gradient states nothing at all.
    static let legendTicks: [Float] = [-120, -90, -60, -30, 0]
}
