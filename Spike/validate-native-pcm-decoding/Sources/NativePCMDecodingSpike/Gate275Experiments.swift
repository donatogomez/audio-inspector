import AVFoundation
import CryptoKit
import Foundation

// Gate 2.75 — characterisation of the samples past `frameLength`.
//
// Gate 2.5 established that, for AAC, *modifications were observed* in that region and that storage
// reuse cannot explain them. This gate characterises the pattern those samples present. It states
// what pattern they show; it does not state what they mean. No external documentation was consulted.
//
// Every buffer here is freshly allocated for every read. Gate 2.5 observed that a fresh
// `AVAudioPCMBuffer` reads as all zero even when the allocator returns a recycled address, so a fresh
// buffer gives a deterministic all-zero baseline without wiping — which is what makes the hashes in
// C5 and C6 meaningful.

// MARK: - Records

struct RegionComparison {
    var channel: Int
    var validCount: Int
    var postCount: Int

    var postAllZero: Bool
    var elementwiseIdentical: Bool
    var maxAbsDifference: Float
    var correlation: Double?

    var validMin: Float
    var validMax: Float
    var validRMS: Double
    var postMin: Float
    var postMax: Float
    var postRMS: Double

    var meanAbsDeltaWithinValid: Double
    var boundaryDelta: Double
    var boundaryRatio: Double?

    var classification: String
}

struct DeterminismRun {
    let index: Int
    let postFrames: Int
    let byteCount: Int
    let sha256: String
}

struct DeterminismObservation {
    let label: String
    var runs: [DeterminismRun] = []
    var allHashesIdentical: Bool?
    var error: String?
}

struct CapacitySensitivity {
    let capacity: Int
    var lastChunkFrameLength: Int?
    var postRegionFrames: Int?
    var modificationsObserved: Bool?
    var sha256: String?
    var classification: String?
    var error: String?
}

struct ContentDependence {
    var alphaHash: String?
    var betaHash: String?
    var hashesEqual: Bool?
    var alphaComparison: [RegionComparison]?
    var betaComparison: [RegionComparison]?
    var alphaDeterminism: DeterminismObservation?
    var betaDeterminism: DeterminismObservation?
    var error: String?
}

// MARK: - Experiments

enum Gate275Experiments {
    static let window = 64
    static let capacities: [AVAudioFrameCount] = [
        31, 32, 33, 63, 64, 65, 127, 128, 129,
        255, 256, 257, 511, 512, 513, 1023, 1024, 1025,
    ]

    /// Reads the whole file, allocating a fresh buffer for every read, and returns the **final**
    /// buffer together with the format. The caller inspects the region past `frameLength` on it.
    static func readLastChunk(url: URL, capacity: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        let file = try AVAudioFile(forReading: url)
        var last: AVAudioPCMBuffer?

        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
                return nil
            }
            try file.read(into: buffer)
            if buffer.frameLength == 0 {
                break
            }
            last = buffer
        }

        return last
    }

    /// The raw bytes of `[frameLength, frameCapacity)`, channel by channel, as little-endian float32.
    static func postRegionBytes(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.floatChannelData else { return Data() }
        let start = Int(buffer.frameLength)
        let capacity = Int(buffer.frameCapacity)
        guard start < capacity else { return Data() }

        var data = Data()
        for channel in 0 ..< Int(buffer.format.channelCount) {
            let samples = channelData[channel]
            for frame in start ..< capacity {
                withUnsafeBytes(of: samples[frame].bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - C4 — what pattern do the post-`frameLength` samples present?

    /// Compares the last `window` valid samples with the first `window` samples past `frameLength`,
    /// per channel. Classification is mechanical, from the metrics below — never from an opinion
    /// about what the samples are.
    static func experimentC4(buffer: AVAudioPCMBuffer) -> [RegionComparison] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let length = Int(buffer.frameLength)
        let capacity = Int(buffer.frameCapacity)
        let validCount = min(window, length)
        let postCount = min(window, capacity - length)
        guard validCount > 1, postCount > 1 else { return [] }

        var comparisons: [RegionComparison] = []

        for channel in 0 ..< Int(buffer.format.channelCount) {
            let samples = channelData[channel]
            let valid = (length - validCount ..< length).map { samples[$0] }
            let post = (length ..< length + postCount).map { samples[$0] }

            let pairCount = min(valid.count, post.count)
            var maxDifference: Float = 0
            var identical = true
            for index in 0 ..< pairCount {
                let difference = abs(valid[valid.count - pairCount + index] - post[index])
                maxDifference = max(maxDifference, difference)
                if difference != 0 {
                    identical = false
                }
            }

            let validSlice = Array(valid.suffix(pairCount))
            let postSlice = Array(post.prefix(pairCount))
            let correlation = pearson(validSlice, postSlice)

            var deltaSum = 0.0
            for index in 1 ..< valid.count {
                deltaSum += Double(abs(valid[index] - valid[index - 1]))
            }
            let meanAbsDelta = valid.count > 1 ? deltaSum / Double(valid.count - 1) : 0
            let boundaryDelta = Double(abs(post[0] - valid[valid.count - 1]))
            let boundaryRatio = meanAbsDelta > 0 ? boundaryDelta / meanAbsDelta : nil

            let validRMS = rms(valid)
            let postRMS = rms(post)
            let postAllZero = post.allSatisfy { $0 == 0 }

            comparisons.append(RegionComparison(
                channel: channel,
                validCount: valid.count,
                postCount: post.count,
                postAllZero: postAllZero,
                elementwiseIdentical: identical,
                maxAbsDifference: maxDifference,
                correlation: correlation,
                validMin: valid.min() ?? 0,
                validMax: valid.max() ?? 0,
                validRMS: validRMS,
                postMin: post.min() ?? 0,
                postMax: post.max() ?? 0,
                postRMS: postRMS,
                meanAbsDeltaWithinValid: meanAbsDelta,
                boundaryDelta: boundaryDelta,
                boundaryRatio: boundaryRatio,
                classification: classify(
                    identical: identical,
                    postAllZero: postAllZero,
                    correlation: correlation,
                    boundaryRatio: boundaryRatio,
                    validRMS: validRMS,
                    postRMS: postRMS
                )
            ))
        }

        return comparisons
    }

    /// Mechanical classification. The thresholds are arbitrary but fixed and stated, so the label is
    /// reproducible; the metrics beside it are the actual evidence.
    ///
    /// - `identical`               — every compared pair is bit-equal.
    /// - `apparent continuation`   — the step across the boundary is no larger than 3× the mean step
    ///                               inside the valid window, **and** the two windows have RMS within
    ///                               a factor of 2 of each other.
    /// - `high correlation`        — |r| ≥ 0.9.
    /// - `low correlation`         — 0.1 ≤ |r| < 0.9.
    /// - `completely different`    — |r| < 0.1, or correlation undefined.
    static func classify(
        identical: Bool,
        postAllZero: Bool,
        correlation: Double?,
        boundaryRatio: Double?,
        validRMS: Double,
        postRMS: Double
    ) -> String {
        if identical {
            return "identical"
        }
        if postAllZero {
            return "completely different (post region is entirely zero)"
        }

        let rmsComparable = validRMS > 0 && postRMS > 0
            && postRMS / validRMS >= 0.5 && postRMS / validRMS <= 2.0
        if let boundaryRatio, boundaryRatio <= 3.0, rmsComparable {
            return "apparent continuation"
        }
        guard let correlation else { return "completely different (correlation undefined)" }
        if abs(correlation) >= 0.9 {
            return "high correlation"
        }
        if abs(correlation) >= 0.1 {
            return "low correlation"
        }
        return "completely different"
    }

    private static func rms(_ values: [Float]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sum = values.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(values.count)).squareRoot()
    }

    private static func pearson(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == b.count, a.count > 1 else { return nil }
        let n = Double(a.count)
        let meanA = a.reduce(0.0) { $0 + Double($1) } / n
        let meanB = b.reduce(0.0) { $0 + Double($1) } / n
        var covariance = 0.0
        var varianceA = 0.0
        var varianceB = 0.0
        for index in a.indices {
            let da = Double(a[index]) - meanA
            let db = Double(b[index]) - meanB
            covariance += da * db
            varianceA += da * da
            varianceB += db * db
        }
        guard varianceA > 0, varianceB > 0 else { return nil }
        return covariance / (varianceA * varianceB).squareRoot()
    }

    // MARK: - C5 — determinism

    static func experimentC5(url: URL, label: String, capacity: AVAudioFrameCount = 4096, runs: Int = 5) -> DeterminismObservation {
        var observation = DeterminismObservation(label: label)

        do {
            for index in 0 ..< runs {
                guard let buffer = try readLastChunk(url: url, capacity: capacity) else {
                    observation.error = "no final chunk was produced on run \(index)"
                    return observation
                }
                let bytes = postRegionBytes(buffer)
                observation.runs.append(DeterminismRun(
                    index: index,
                    postFrames: Int(buffer.frameCapacity) - Int(buffer.frameLength),
                    byteCount: bytes.count,
                    sha256: sha256(bytes)
                ))
            }
            let hashes = Set(observation.runs.map(\.sha256))
            observation.allHashesIdentical = hashes.count == 1
        } catch {
            observation.error = Describe.error(error)
        }

        return observation
    }

    // MARK: - C6 — capacity sensitivity of the final chunk

    static func experimentC6(url: URL) -> [CapacitySensitivity] {
        capacities.map { capacity in
            var record = CapacitySensitivity(capacity: Int(capacity))
            do {
                guard let buffer = try readLastChunk(url: url, capacity: capacity) else {
                    record.error = "no final chunk was produced"
                    return record
                }
                let length = Int(buffer.frameLength)
                let post = Int(buffer.frameCapacity) - length
                record.lastChunkFrameLength = length
                record.postRegionFrames = post

                guard post > 0 else {
                    record.modificationsObserved = nil // no region existed — not evaluated
                    return record
                }

                let bytes = postRegionBytes(buffer)
                record.sha256 = sha256(bytes)
                // The buffer was freshly allocated (observed all-zero baseline), so any non-zero value
                // in the region is a modification relative to that baseline.
                record.modificationsObserved = !isAllZero(buffer)
                record.classification = experimentC4(buffer: buffer).first?.classification
            } catch {
                record.error = Describe.error(error)
            }
            return record
        }
    }

    /// Follow-up to C6, added because the C6 table showed **identical hashes whenever the post-region
    /// length matched**, at capacities whose final chunks began at different absolute positions
    /// (capacity 64 and 128 both yielded 60 post frames and the same hash; capacities 129 and 513 both
    /// yielded 18 and the same hash).
    ///
    /// This checks the obvious next question objectively: is every shorter post region an exact
    /// **prefix** of the longest one? A yes turns "the hashes happened to collide" into "the content
    /// is a fixed sequence, exposed to whatever length the capacity leaves". It asserts nothing about
    /// what that sequence is.
    static func experimentC6PrefixCheck(url: URL) -> [(capacity: Int, frames: Int, isPrefixOfLongest: Bool?)] {
        var regions: [(capacity: Int, samples: [[Float]])] = []

        for capacity in capacities {
            guard
                let buffer = try? readLastChunk(url: url, capacity: capacity),
                let channelData = buffer.floatChannelData
            else { continue }
            let start = Int(buffer.frameLength)
            let end = Int(buffer.frameCapacity)
            guard start < end else {
                regions.append((Int(capacity), []))
                continue
            }
            let samples = (0 ..< Int(buffer.format.channelCount)).map { channel in
                (start ..< end).map { channelData[channel][$0] }
            }
            regions.append((Int(capacity), samples))
        }

        guard let longest = regions.max(by: { ($0.samples.first?.count ?? 0) < ($1.samples.first?.count ?? 0) }),
              !longest.samples.isEmpty
        else { return regions.map { ($0.capacity, 0, nil) } }

        return regions.map { region in
            let frames = region.samples.first?.count ?? 0
            guard frames > 0 else { return (region.capacity, 0, nil) }
            var isPrefix = true
            for channel in region.samples.indices where channel < longest.samples.count {
                let candidate = region.samples[channel]
                let reference = longest.samples[channel]
                guard candidate.count <= reference.count else { isPrefix = false; break }
                for index in candidate.indices where candidate[index] != reference[index] {
                    isPrefix = false
                    break
                }
                if !isPrefix {
                    break
                }
            }
            return (region.capacity, frames, isPrefix)
        }
    }

    private static func isAllZero(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData else { return false }
        let start = Int(buffer.frameLength)
        let capacity = Int(buffer.frameCapacity)
        for channel in 0 ..< Int(buffer.format.channelCount) {
            let samples = channelData[channel]
            for frame in start ..< capacity where samples[frame] != 0 {
                return false
            }
        }
        return true
    }

    // MARK: - C7 — does the region depend on the audio content?

    /// Two AAC files of identical structure (same sample rate, channels, frame count) and **different
    /// content**, so the only variable is the audio itself.
    static func experimentC7(directory: URL) -> ContentDependence {
        var observation = ContentDependence()
        let alpha = directory.appendingPathComponent("aac-alpha.m4a")
        let beta = directory.appendingPathComponent("aac-beta.m4a")

        do {
            try FixtureFactory.writeAAC(to: alpha, content: .alpha)
            try FixtureFactory.writeAAC(to: beta, content: .beta)

            guard
                let alphaBuffer = try readLastChunk(url: alpha, capacity: 4096),
                let betaBuffer = try readLastChunk(url: beta, capacity: 4096)
            else {
                observation.error = "no final chunk was produced for one of the two files"
                return observation
            }

            observation.alphaComparison = experimentC4(buffer: alphaBuffer)
            observation.betaComparison = experimentC4(buffer: betaBuffer)
            observation.alphaHash = sha256(postRegionBytes(alphaBuffer))
            observation.betaHash = sha256(postRegionBytes(betaBuffer))
            observation.hashesEqual = observation.alphaHash == observation.betaHash
            observation.alphaDeterminism = experimentC5(url: alpha, label: "AAC alpha")
            observation.betaDeterminism = experimentC5(url: beta, label: "AAC beta")
        } catch {
            observation.error = Describe.error(error)
        }

        return observation
    }
}
