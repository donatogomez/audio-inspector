import AVFoundation
import Foundation

/// Experiments A and B. Nothing else is implemented yet — C to K arrive in later gates, deliberately
/// separated so a format-compatibility result cannot be mistaken for a concurrency or architecture
/// result.
enum Experiments {
    /// Chunk size for experiment B. One value only at this gate; experiment F varies it later, so no
    /// conclusion about chunk sizing may be drawn from this number.
    static let chunkFrames: AVAudioFrameCount = 4096

    /// Safety cap so a decoder that never signals EOF ends the run instead of hanging it. Reaching
    /// it is itself an observation and is recorded as such — never silently treated as EOF.
    static let maxChunks = 100_000

    /// **A — open, formats, frame length.** Opens the file for reading and records what the API says
    /// about it. Opening is attempted regardless of how generation went: a file that failed to
    /// generate simply will not be here, and that is recorded separately.
    ///
    /// Returns the opened file so experiment B can continue on the same instance with the cursor at
    /// zero, which is also the realistic reading path.
    static func experimentA(url: URL, into observation: inout FormatObservation) -> AVAudioFile? {
        do {
            let file = try AVAudioFile(forReading: url)
            observation.opened = true
            observation.fileFormat = Describe.format(file.fileFormat)
            observation.processingFormat = Describe.format(file.processingFormat)
            observation.fileFormatInterleaved = file.fileFormat.isInterleaved
            observation.processingFormatInterleaved = file.processingFormat.isInterleaved
            observation.channels = file.processingFormat.channelCount
            observation.sampleRate = file.processingFormat.sampleRate
            observation.declaredLength = file.length
            return file
        } catch {
            observation.opened = false
            observation.openError = Describe.error(error)
            return nil
        }
    }

    /// **B — incremental read to EOF.** Reads in fixed-size chunks until the decoder stops returning
    /// frames, counting what actually comes back rather than trusting `length`.
    ///
    /// EOF is observed, not assumed: the loop does not stop at `framePosition >= length`, because
    /// whether those two agree is precisely the question. It stops when a read returns zero frames,
    /// when it throws, or when the safety cap is reached — and records which of the three happened.
    static func experimentB(file: AVAudioFile, into observation: inout FormatObservation) {
        observation.readAttempted = true

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames) else {
            observation.readError = "AVAudioPCMBuffer(pcmFormat:frameCapacity:) returned nil for the processing format"
            return
        }

        var totalFrames: Int64 = 0
        var chunks = 0
        var firstChunk: Int64?
        var lastChunk: Int64?

        while true {
            do {
                try file.read(into: buffer)
            } catch {
                observation.readError = Describe.error(error)
                observation.eofSignal = "read(into:) threw after \(chunks) chunk(s)"
                break
            }

            let framesThisChunk = Int64(buffer.frameLength)
            if framesThisChunk == 0 {
                observation.eofSignal = "read(into:) returned frameLength == 0 without throwing"
                break
            }

            totalFrames += framesThisChunk
            chunks += 1
            if firstChunk == nil {
                firstChunk = framesThisChunk
            }
            lastChunk = framesThisChunk

            if chunks >= maxChunks {
                observation.eofSignal = "SAFETY CAP reached (\(maxChunks) chunks) — EOF was never signalled"
                break
            }
        }

        observation.framesRead = totalFrames
        observation.chunkCount = chunks
        observation.firstChunkFrames = firstChunk
        observation.lastChunkFrames = lastChunk
        observation.framePositionAtStop = file.framePosition
    }

    /// **B, control.** The same read on a freshly opened instance, but stopping on
    /// `framePosition < length` instead of on whatever the decoder does at the end.
    ///
    /// This is not a second experiment: it exists so the stop observed in `experimentB` can be
    /// attributed. If this loop completes without throwing while the unguarded one throws, the throw
    /// belongs to reading *past* the end — not to a defect in the reading loop, and not to the format.
    static func experimentBControl(url: URL, into observation: inout FormatObservation) {
        observation.guardedAttempted = true

        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames) else {
                observation.guardedError = "AVAudioPCMBuffer(pcmFormat:frameCapacity:) returned nil"
                return
            }

            var totalFrames: Int64 = 0
            var chunks = 0
            observation.guardedThrew = false

            while file.framePosition < file.length {
                try file.read(into: buffer)
                let framesThisChunk = Int64(buffer.frameLength)
                if framesThisChunk == 0 {
                    break
                } // recorded by the counters below, not assumed
                totalFrames += framesThisChunk
                chunks += 1
                if chunks >= maxChunks {
                    break
                }
            }

            observation.guardedFramesRead = totalFrames
            observation.guardedChunkCount = chunks
            observation.guardedFinalFramePosition = file.framePosition
        } catch {
            observation.guardedThrew = true
            observation.guardedError = Describe.error(error)
        }
    }
}
