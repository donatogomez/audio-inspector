import AudioInspectorDomain
import CoreGraphics

/// Where each cell of the model lands inside the area available to draw it.
///
/// Deliberately outside the view, for the reason `WaveformGeometry` is: a `Canvas` renderer cannot be
/// asserted, and every property worth guaranteeing here — that 0 Hz is at the bottom and Nyquist at the
/// top, that the first column is leftmost, that the cells tile the area with no gap — is arithmetic
/// that needs no rendering at all.
///
/// It maps the model onto whatever size it is given and never the other way round. The model is
/// resolution-independent by construction, so a resize re-runs this and nothing else: the file is not
/// read again, no transform runs again, and the model is not touched. Sizes are in **points**; no
/// screen scale appears anywhere, because the drawing is resolution-independent and the renderer owns
/// the device pixels.
struct SpectrogramGeometry: Equatable {
    /// The least a cell may occupy. Without it a model with more columns than the area has points would
    /// round cells away to nothing and leave gaps that read as silence.
    static let minimumCellSize: CGFloat = 1

    let size: CGSize
    let columnCount: Int
    let bandCount: Int

    /// Fails on an area nothing can be drawn in, and on a model with no cells.
    ///
    /// All of those are ordinary situations rather than errors: a `Canvas` is laid out at zero size
    /// before it settles, and a file shorter than one analysis window legitimately has no columns. The
    /// caller states the fact in words instead.
    init?(size: CGSize, columnCount: Int, bandCount: Int) {
        guard size.width > 0, size.height > 0, columnCount > 0, bandCount > 0 else { return nil }
        self.size = size
        self.columnCount = columnCount
        self.bandCount = bandCount
    }

    init?(size: CGSize, model: Spectrogram) {
        self.init(size: size, columnCount: model.columnCount, bandCount: model.bandCount)
    }

    /// The horizontal band belonging to a column, or `nil` outside the model.
    ///
    /// Both edges are computed from the index rather than accumulated from a step, so rounding cannot
    /// drift across 1024 columns and one column's trailing edge is exactly the next one's leading edge:
    /// the bands tile the width with no gap and no overlap, at any width.
    func horizontalBand(forColumn index: Int) -> (minX: CGFloat, maxX: CGFloat)? {
        guard index >= 0, index < columnCount else { return nil }
        return (
            minX: size.width * CGFloat(index) / CGFloat(columnCount),
            maxX: size.width * CGFloat(index + 1) / CGFloat(columnCount)
        )
    }

    /// The vertical band belonging to a frequency band, or `nil` outside the model.
    ///
    /// **Band 0 is at the bottom.** The model's bands run from 0 Hz upwards, and a drawing that put the
    /// lowest frequency at the top would be upside down against every convention a reader has — so the
    /// index is flipped exactly once, here, rather than in the renderer.
    func verticalBand(forBand index: Int) -> (minY: CGFloat, maxY: CGFloat)? {
        guard index >= 0, index < bandCount else { return nil }
        let flipped = bandCount - 1 - index
        return (
            minY: size.height * CGFloat(flipped) / CGFloat(bandCount),
            maxY: size.height * CGFloat(flipped + 1) / CGFloat(bandCount)
        )
    }

    /// The rectangle drawn for one cell.
    ///
    /// Its width and height are widened to `minimumCellSize` when the area is smaller than the model,
    /// so no cell disappears; the position is still the cell's own, so nothing shifts.
    func cell(column: Int, band: Int) -> CGRect? {
        guard let horizontal = horizontalBand(forColumn: column),
              let vertical = verticalBand(forBand: band)
        else { return nil }
        return CGRect(
            x: horizontal.minX,
            y: vertical.minY,
            width: max(horizontal.maxX - horizontal.minX, Self.minimumCellSize),
            height: max(vertical.maxY - vertical.minY, Self.minimumCellSize)
        )
    }

    /// The vertical position of a frequency, with 0 Hz at the bottom edge and `nyquist` at the top.
    ///
    /// Linear, always. The artefact a reader is looking for is a horizontal edge in the 16–20 kHz
    /// region, and on a logarithmic axis that whole region compresses into the top sliver and stops
    /// being readable (design.md §5).
    func y(forFrequency frequency: Double, nyquist: Double) -> CGFloat? {
        guard nyquist > 0, frequency >= 0, frequency <= nyquist else { return nil }
        return size.height - size.height * CGFloat(frequency / nyquist)
    }

    /// The horizontal position of a moment, with the first column's start at the left edge.
    func x(forTime seconds: Double, duration: Double) -> CGFloat? {
        guard duration > 0, seconds >= 0, seconds <= duration else { return nil }
        return size.width * CGFloat(seconds / duration)
    }
}
