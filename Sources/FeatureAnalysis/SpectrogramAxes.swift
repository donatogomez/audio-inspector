import AudioInspectorDomain
import Foundation

/// Which marks the axes carry, chosen from the file alone.
///
/// **The marks are a function of the file, never of the window.** A reader who widens the window must
/// not see different evidence, so nothing here consults a size: a wider drawing shows the same marks
/// further apart. Only *whether* a mark is legible is the view's business, and the view solves that by
/// giving the axis room rather than by dropping marks.
enum SpectrogramAxes {
    /// The frequency marks for a file, from 0 Hz to its own Nyquist.
    ///
    /// **The axis is never cropped.** A 96 kHz file that holds nothing above 22 kHz is showing exactly
    /// the thing a collector is looking for, and cropping to 24 kHz would hide it (design.md §5). The
    /// empty space above the content is evidence, and it stays.
    ///
    /// The step is chosen so the marks stay countable at every rate rather than fixed: a 2 kHz step is
    /// right at 44.1 kHz and would print 48 labels at 192 kHz.
    static func frequencyMarks(nyquist: Double) -> [Double] {
        guard nyquist > 0 else { return [] }
        let step = frequencyStep(nyquist: nyquist)
        var marks: [Double] = []
        var value = 0.0
        while value < nyquist {
            marks.append(value)
            value += step
        }
        // Nyquist itself always appears, exactly, however the step fell — it is the top of the axis and
        // the number a reader checks the file's rate against.
        if marks.last != nyquist { marks.append(nyquist) }
        return marks
    }

    /// Roughly six to twelve marks at any sample rate, on a round number of kHz.
    static func frequencyStep(nyquist: Double) -> Double {
        let candidates: [Double] = [1_000, 2_000, 5_000, 10_000, 20_000, 25_000, 50_000]
        let target = nyquist / 8
        return candidates.first { $0 >= target } ?? candidates[candidates.count - 1]
    }

    /// The time marks for a file of the given duration, in seconds.
    ///
    /// Deliberately coarse. The drawing folds the whole file into at most 1024 columns, so a column of
    /// a five-minute file covers roughly 300 ms; printing milliseconds would promise a precision the
    /// picture cannot be read to.
    static func timeMarks(duration: Double) -> [Double] {
        guard duration > 0 else { return [] }
        let step = timeStep(duration: duration)
        var marks: [Double] = []
        var value = 0.0
        while value < duration {
            marks.append(value)
            value += step
        }
        if marks.last != duration { marks.append(duration) }
        return marks
    }

    static func timeStep(duration: Double) -> Double {
        let candidates: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1_800, 3_600]
        let target = duration / 6
        return candidates.first { $0 >= target } ?? candidates[candidates.count - 1]
    }

    /// A file's duration in seconds, from the model alone.
    static func duration(of model: Spectrogram) -> Double {
        guard model.sampleRate > 0 else { return 0 }
        return Double(model.frameCount) / model.sampleRate
    }
}
