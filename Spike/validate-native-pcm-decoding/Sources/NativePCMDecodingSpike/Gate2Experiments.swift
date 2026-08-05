import AVFoundation
import Foundation

/// Experiments C, D and E. F to K are not implemented and nothing about them may be inferred here.
enum Gate2Experiments {
    /// Written into the buffer before every read in the sentinel pass. Chosen far outside anything
    /// audio can legitimately contain, so "still the sentinel" is unambiguous.
    static let sentinel: Float = -999.0

    // MARK: - C — PCM layout

    /// Records what the buffer physically is, and checks the one thing a chunked reader depends on:
    /// that `frameLength` is a real bound.
    ///
    /// Two passes, because they answer two different questions that a single pass would conflate:
    /// whether the **decoder** writes past `frameLength` (sentinel pass), and whether the region past
    /// `frameLength` still holds the **previous chunk's** samples (no-wipe pass). The second is the
    /// dangerous one: the data there looks valid.
    static func experimentC(url: URL, fixture: String) -> LayoutObservation {
        var observation = LayoutObservation(fixture: fixture)

        do {
            // — Pass 1: sentinel —
            let file = try AVAudioFile(forReading: url)
            observation.fileFormatInterleaved = file.fileFormat.isInterleaved
            observation.processingFormatInterleaved = file.processingFormat.isInterleaved

            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Experiments.chunkFrames) else {
                observation.error = "AVAudioPCMBuffer returned nil"
                return observation
            }
            observation.frameCapacity = buffer.frameCapacity
            observation.floatChannelDataAvailable = buffer.floatChannelData != nil

            let channelCount = Int(format.channelCount)
            let capacity = Int(buffer.frameCapacity)
            var chunks = 0
            var firstChunk: Int64?
            var lastChunk: Int64?
            var wroteBeyond = false

            while file.framePosition < file.length {
                if let channelData = buffer.floatChannelData {
                    buffer.frameLength = buffer.frameCapacity
                    for channel in 0 ..< channelCount {
                        let samples = channelData[channel]
                        for frame in 0 ..< capacity {
                            samples[frame] = sentinel
                        }
                    }
                }

                try file.read(into: buffer)
                let frames = Int(buffer.frameLength)
                if frames == 0 {
                    break
                }

                if let channelData = buffer.floatChannelData, frames < capacity {
                    for channel in 0 ..< channelCount {
                        let samples = channelData[channel]
                        for frame in frames ..< capacity where samples[frame] != sentinel {
                            wroteBeyond = true
                            break
                        }
                    }
                }

                chunks += 1
                if firstChunk == nil {
                    firstChunk = Int64(frames)
                }
                lastChunk = Int64(frames)
            }

            observation.chunkCount = chunks
            observation.firstChunkFrames = firstChunk
            observation.lastChunkFrames = lastChunk
            observation.decoderWroteBeyondFrameLength = wroteBeyond

            // The AudioBufferList is read after a real read, so it describes a populated buffer.
            //
            // It must be walked through `UnsafeMutableAudioBufferListPointer`. `AudioBufferList` ends
            // in a C variable-length array, so copying the struct out (`.pointee`) and indexing past
            // `mBuffers[0]` reads memory that is not part of the copy — it produces plausible-looking
            // garbage rather than a diagnostic. An earlier version of this experiment did exactly
            // that and reported nonsense for the second buffer.
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            observation.numberBuffers = UInt32(list.count)
            observation.channelsPerBuffer = list.map(\.mNumberChannels)
            observation.dataByteSizePerBuffer = list.map(\.mDataByteSize)

            // — Pass 2: no wipe, to see whether the tail keeps the previous chunk's samples —
            let secondFile = try AVAudioFile(forReading: url)
            guard let secondBuffer = AVAudioPCMBuffer(pcmFormat: secondFile.processingFormat, frameCapacity: Experiments.chunkFrames) else {
                return observation
            }
            var snapshot = [[Float]](repeating: [Float](repeating: 0, count: capacity), count: channelCount)
            var retains: Bool?

            while secondFile.framePosition < secondFile.length {
                if let channelData = secondBuffer.floatChannelData {
                    for channel in 0 ..< channelCount {
                        let samples = channelData[channel]
                        for frame in 0 ..< capacity {
                            snapshot[channel][frame] = samples[frame]
                        }
                    }
                }

                try secondFile.read(into: secondBuffer)
                let frames = Int(secondBuffer.frameLength)
                if frames == 0 {
                    break
                }

                if frames < capacity, let channelData = secondBuffer.floatChannelData {
                    var identical = true
                    for channel in 0 ..< channelCount {
                        let samples = channelData[channel]
                        for frame in frames ..< capacity where samples[frame] != snapshot[channel][frame] {
                            identical = false
                            break
                        }
                    }
                    retains = identical
                }
            }
            observation.tailRetainsPreviousChunk = retains
        } catch {
            observation.error = Describe.error(error)
        }

        return observation
    }

    // MARK: - D — multichannel

    static func experimentD(directory: URL) -> MultichannelObservation {
        var observation = MultichannelObservation()
        let url = directory.appendingPathComponent("multichannel.wav")

        // Attempt 1: plain settings, no explicit channel layout.
        do {
            observation.framesWritten = try FixtureFactory.writeMultichannel(to: url, withLayout: false)
            observation.generatedWithoutLayout = true
            observation.layoutUsed = "none (plain settings accepted)"
        } catch {
            observation.generatedWithoutLayout = false
            observation.generationErrorWithoutLayout = Describe.error(error)

            // Attempt 2: with an explicit quadraphonic layout. Recorded as a second attempt, not
            // substituted for the first — needing a layout is itself an observation.
            try? FileManager.default.removeItem(at: url)
            do {
                observation.framesWritten = try FixtureFactory.writeMultichannel(to: url, withLayout: true)
                observation.generatedWithLayout = true
                observation.layoutUsed = "kAudioChannelLayoutTag_Quadraphonic"
            } catch {
                observation.generatedWithLayout = false
                observation.generationErrorWithLayout = Describe.error(error)
                return observation
            }
        }

        do {
            let file = try AVAudioFile(forReading: url)
            observation.opened = true
            observation.fileFormat = Describe.format(file.fileFormat)
            observation.processingFormat = Describe.format(file.processingFormat)
            observation.declaredLength = file.length
            observation.channels = file.processingFormat.channelCount

            let channelCount = Int(file.processingFormat.channelCount)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: Experiments.chunkFrames) else {
                observation.readError = "AVAudioPCMBuffer returned nil"
                return observation
            }

            var minimum = [Float](repeating: .greatestFiniteMagnitude, count: channelCount)
            var maximum = [Float](repeating: -.greatestFiniteMagnitude, count: channelCount)
            var sum = [Double](repeating: 0, count: channelCount)
            var maxError = [Float](repeating: 0, count: channelCount)
            var total: Int64 = 0
            var chunks = 0

            while file.framePosition < file.length {
                try file.read(into: buffer)
                let frames = Int(buffer.frameLength)
                if frames == 0 {
                    break
                }
                chunks += 1
                total += Int64(frames)

                if let channelData = buffer.floatChannelData {
                    for channel in 0 ..< channelCount {
                        let expected = FixtureFactory.multichannelValue(channel: channel)
                        let samples = channelData[channel]
                        for frame in 0 ..< frames {
                            let value = samples[frame]
                            minimum[channel] = Swift.min(minimum[channel], value)
                            maximum[channel] = Swift.max(maximum[channel], value)
                            sum[channel] += Double(value)
                            maxError[channel] = Swift.max(maxError[channel], abs(value - expected))
                        }
                    }
                }
            }

            observation.framesRead = total
            observation.chunkCount = chunks
            observation.expectedPerChannel = (0 ..< channelCount).map { FixtureFactory.multichannelValue(channel: $0) }
            observation.minPerChannel = minimum
            observation.maxPerChannel = maximum
            observation.meanPerChannel = total > 0 ? sum.map { $0 / Double(total) } : nil
            observation.maxAbsErrorPerChannel = maxError

            // Duplication check: two channels reading the same constant would mean the decoder
            // duplicated one. Compared on the observed means, not on the expectation.
            if let means = observation.meanPerChannel {
                var duplicated = false
                for i in means.indices {
                    for j in means.indices where j > i && abs(means[i] - means[j]) < 1e-6 {
                        duplicated = true
                    }
                }
                observation.anyChannelPairIdentical = duplicated
            }
        } catch {
            observation.openError = Describe.error(error)
        }

        return observation
    }

    // MARK: - E — values inside and outside the nominal range

    static func experimentE(directory: URL) -> RangeObservation {
        var observation = RangeObservation()
        let url = directory.appendingPathComponent("float-range.wav")

        do {
            observation.framesWritten = try FixtureFactory.writeRange(to: url)
            observation.generated = true
        } catch {
            observation.generated = false
            observation.generationError = Describe.error(error)
            observation.notTestedReason = "the float fixture could not be written: \(Describe.error(error))"
            return observation
        }

        do {
            let file = try AVAudioFile(forReading: url)
            observation.opened = true
            observation.fileFormat = Describe.format(file.fileFormat)
            observation.processingFormat = Describe.format(file.processingFormat)
            observation.declaredLength = file.length

            let channelCount = Int(file.processingFormat.channelCount)
            let frames = AVAudioFrameCount(file.length)
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                observation.readError = "AVAudioPCMBuffer returned nil, or length was not positive"
                return observation
            }

            try file.read(into: buffer)
            let framesRead = Int(buffer.frameLength)
            observation.framesRead = Int64(framesRead)

            guard let channelData = buffer.floatChannelData else {
                observation.readError = "the processing format exposes no floatChannelData"
                return observation
            }

            var written: [[Float]] = []
            var read: [[Float]] = []
            var minimum: [Float] = []
            var maximum: [Float] = []
            var maxError: [Float] = []

            for channel in 0 ..< channelCount {
                let samples = channelData[channel]
                var channelWritten: [Float] = []
                var channelRead: [Float] = []
                var channelMin = Float.greatestFiniteMagnitude
                var channelMax = -Float.greatestFiniteMagnitude
                var channelError: Float = 0

                for frame in 0 ..< framesRead {
                    let expected = FixtureFactory.rangeValue(channel: channel, frame: frame)
                    let actual = samples[frame]
                    channelWritten.append(expected)
                    channelRead.append(actual)
                    channelMin = Swift.min(channelMin, actual)
                    channelMax = Swift.max(channelMax, actual)
                    channelError = Swift.max(channelError, abs(actual - expected))
                }

                written.append(channelWritten)
                read.append(channelRead)
                minimum.append(channelMin)
                maximum.append(channelMax)
                maxError.append(channelError)
            }

            observation.writtenPerChannel = written
            observation.readPerChannel = read
            observation.minPerChannel = minimum
            observation.maxPerChannel = maximum
            observation.maxAbsErrorPerChannel = maxError
            observation.verdict = verdict(written: written, read: read, minimum: minimum, maximum: maximum)
        } catch {
            observation.readError = Describe.error(error)
        }

        return observation
    }

    /// Derived strictly from the compared samples. Never a guess: when the numbers fit none of the
    /// named shapes, it says so and leaves the samples to speak.
    private static func verdict(written: [[Float]], read: [[Float]], minimum: [Float], maximum: [Float]) -> String {
        let tolerance: Float = 1e-6
        var allEqual = true
        var clippedAtUnit = true

        for channel in written.indices where channel < read.count {
            for frame in written[channel].indices where frame < read[channel].count {
                let expected = written[channel][frame]
                let actual = read[channel][frame]
                if abs(actual - expected) > tolerance {
                    allEqual = false
                }
                let clampedExpectation = Swift.max(-1, Swift.min(1, expected))
                if abs(actual - clampedExpectation) > tolerance {
                    clippedAtUnit = false
                }
            }
        }

        if allEqual {
            return "preserved — every sample read back exactly as written, including beyond ±1"
        }
        if clippedAtUnit {
            return "clipped at ±1 — values beyond the nominal range were clamped"
        }
        let observedMax = maximum.max() ?? 0
        let observedMin = minimum.min() ?? 0
        return "neither preserved nor clamped at ±1 — observed range [\(observedMin), \(observedMax)]; see the samples"
    }
}
