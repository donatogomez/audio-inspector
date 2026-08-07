import AudioInspectorDomain
import CoreGraphics
import Foundation

/// The spectrogram's cells as a single image, one **logical pixel per model cell**.
///
/// ## Why an image rather than a shape per cell
///
/// The first renderer filled one rectangle per cell inside a `Canvas`. That is up to 524 288 fills for
/// one drawing, and it was measured at **213 ms in Release and 611 ms in Debug** — *per redraw*, and a
/// `Canvas` redraws on every size change, so a live resize paid it on every frame. Building this buffer
/// costs **6.5 ms** and drawing the resulting image costs **0.1 ms**, whatever the width
/// (`docs/spikes/2026-08-07-spectrogram-performance-presentation-diagnosis.md`, §D).
///
/// The saving is structural rather than clever: the work becomes a function of the **model**, which
/// never changes once produced, instead of a function of the **area**, which changes constantly.
///
/// ## What it is not allowed to do
///
/// - **No interpolation.** The image carries exactly the model's own cells and is drawn with
///   interpolation disabled, so nothing between two measured levels is ever invented. For an instrument
///   whose subject is *where energy stops*, a smoothed edge would be the wrong artefact.
/// - **No resampling to the view.** The image is the model's size — at most 1024 × 512 — and the view
///   scales it. Scaling is the renderer's business; the evidence is not touched.
/// - **No change to `Spectrogram`.** The domain gains no CoreGraphics and knows nothing about pixels.
///   Values above 0 dBFS are still kept exactly as measured; the clamp lives in the colour ramp and
///   applies only to where a level sits on the ramp.
///
/// ## Orientation
///
/// Band 0 is the lowest frequency and must appear at the **bottom**, so row `bandCount - 1 - band` is
/// written — the same single flip `SpectrogramGeometry.verticalBand` performs, done once per row here
/// instead of once per cell. Column 0 is leftmost, so time runs left to right.
enum SpectrogramRaster {
    /// Bytes per pixel in the RGBA8 buffer this builds.
    static let bytesPerPixel = 4

    /// One model's cells, laid out as RGBA8 rows ready for `CGImage`.
    ///
    /// Exposed so a test can assert a pixel rather than look at one, and so `image(for:)` has exactly
    /// one implementation of the layout to be wrong about.
    struct Buffer: Equatable {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        var bytesPerRow: Int { width * SpectrogramRaster.bytesPerPixel }
    }

    /// The buffer for a model, or `nil` when there is nothing to draw or the size cannot be represented.
    ///
    /// A model with no columns is an ordinary outcome — a file shorter than one analysis window — and
    /// the caller states it in words rather than drawing an empty box.
    static func buffer(for model: Spectrogram) -> Buffer? {
        let width = model.columnCount
        let height = model.bandCount
        guard width > 0, height > 0 else { return nil }

        // The production caps make an overflow unreachable, but a buffer size is exactly the kind of
        // multiplication that turns a bad input into a wild write, so it is checked rather than assumed.
        let rowProduct = width.multipliedReportingOverflow(by: bytesPerPixel)
        guard !rowProduct.overflow else { return nil }
        let byteProduct = rowProduct.partialValue.multipliedReportingOverflow(by: height)
        guard !byteProduct.overflow else { return nil }

        let rowBytes = rowProduct.partialValue
        var pixels = [UInt8](repeating: 0, count: byteProduct.partialValue)

        for band in 0 ..< height {
            let row = height - 1 - band          // band 0 at the bottom
            let rowStart = row * rowBytes
            for column in 0 ..< width {
                // Read through the model's own accessor: the layout is its business, not this type's.
                guard let value = model.value(column: column, band: band) else { continue }
                let components = SpectrogramColourRamp.components(for: value)
                let offset = rowStart + column * bytesPerPixel
                pixels[offset] = byte(components.red)
                pixels[offset + 1] = byte(components.green)
                pixels[offset + 2] = byte(components.blue)
                pixels[offset + 3] = 255
            }
        }

        return Buffer(pixels: pixels, width: width, height: height)
    }

    /// The image for a model, built from `buffer(for:)` so the two cannot disagree about the layout.
    static func image(for model: Spectrogram) -> CGImage? {
        buffer(for: model).flatMap(image(from:))
    }

    /// Wraps an already-built buffer. Separate from `buffer(for:)` because the per-pixel work is worth
    /// doing away from the main actor while this part — which only hands CoreGraphics a pointer — is
    /// not, and `Buffer` is `Sendable` where `CGImage` is not.
    static func image(from buffer: Buffer) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(buffer.pixels) as CFData) else { return nil }

        return CGImage(
            width: buffer.width,
            height: buffer.height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * bytesPerPixel,
            bytesPerRow: buffer.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            // The one flag that keeps this honest at every drawn size.
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// A colour component as an 8-bit channel, clamped defensively: the ramp's stops all sit inside
    /// `0...1` and interpolation between them cannot leave that range, but a byte conversion is not the
    /// place to find out otherwise.
    private static func byte(_ component: Double) -> UInt8 {
        UInt8(max(0, min(255, (component * 255).rounded())))
    }
}
