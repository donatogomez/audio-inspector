import AVFoundation
import Foundation

// Gate 2.5 — buffer lifetime investigation.
//
// Gate 2 recorded *that* the region past `frameLength` is never empty. This gate exists to find out
// *what is observable* about why, experimentally rather than from documentation.
//
// Vocabulary discipline, applied throughout: a value that differs from what was placed there is
// recorded as "modifications were observed", never as "the decoder wrote". Attribution is a
// hypothesis and lives in the report's hypothesis section, not in a field name.

// MARK: - Records

/// One read's addresses and sizes.
struct AddressSample {
    let readIndex: Int
    let frameCapacity: UInt32
    let frameLength: UInt32
    let floatChannelDataAddresses: [UInt]
    let audioBufferDataAddresses: [UInt]
}

struct BufferLifetimeObservation {
    let fixture: String

    // Addresses
    var firstRead: AddressSample?
    var secondRead: AddressSample?
    var sameBufferAddressesStableAcrossReads: Bool?
    var floatChannelDataMatchesAudioBufferData: Bool?
    var distinctBufferAAddresses: [UInt]?
    var distinctBufferBAddresses: [UInt]?
    var distinctBuffersHaveDistinctStorage: Bool?

    /// Condition 1 — one buffer reused, nothing wiped
    var reusedNoWipe_tailIdenticalToPreReadContents: Bool?

    /// Condition 2 — one buffer reused, whole capacity wiped with a sentinel before every read
    var reusedWiped_tailModified: Bool?

    // Condition 3 — a brand-new buffer allocated for every read, nothing wiped
    var fresh_tailAllZero: Bool?
    var fresh_tailIdenticalToPreviousReadContents: Bool?
    var fresh_storageAddressReusedAcrossReads: Bool?
    var fresh_addressesPerRead: [[UInt]]?

    var error: String?
}

struct ChunkSizeObservation {
    let fixture: String
    let capacity: UInt32

    var declaredLength: Int64?
    var reads: Int?
    var totalFrames: Int64?
    var minFrameLength: UInt32?
    var maxFrameLength: UInt32?
    var shortReadsBeforeLast: Int?
    var lastReadFrames: UInt32?
    var tailEverExisted: Bool?

    /// Sentinel pass: was anything in `[frameLength, frameCapacity)` different from the sentinel?
    var wiped_tailModified: Bool?
    /// No-wipe pass: did the tail still hold exactly what was there before the read?
    var noWipe_tailIdenticalToPreReadContents: Bool?
    /// No-wipe pass: did any part of the tail differ from what was there before the read?
    var noWipe_tailChanged: Bool?

    var error: String?
}

// MARK: - Experiments

enum Gate25Experiments {
    static let sentinel: Float = -999.0
    static let capacities: [AVAudioFrameCount] = [1, 2, 3, 7, 31, 64, 127, 1024, 4096]

    private static func addresses(of buffer: AVAudioPCMBuffer, readIndex: Int) -> AddressSample {
        let channelCount = Int(buffer.format.channelCount)
        var floatAddresses: [UInt] = []
        if let channelData = buffer.floatChannelData {
            for channel in 0 ..< channelCount {
                floatAddresses.append(UInt(bitPattern: channelData[channel]))
            }
        }
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let dataAddresses = list.map { UInt(bitPattern: $0.mData) }

        return AddressSample(
            readIndex: readIndex,
            frameCapacity: buffer.frameCapacity,
            frameLength: buffer.frameLength,
            floatChannelDataAddresses: floatAddresses,
            audioBufferDataAddresses: dataAddresses
        )
    }

    private static func fill(_ buffer: AVAudioPCMBuffer, with value: Float) {
        guard let channelData = buffer.floatChannelData else { return }
        buffer.frameLength = buffer.frameCapacity
        let capacity = Int(buffer.frameCapacity)
        for channel in 0 ..< Int(buffer.format.channelCount) {
            let samples = channelData[channel]
            for frame in 0 ..< capacity {
                samples[frame] = value
            }
        }
    }

    private static func snapshot(_ buffer: AVAudioPCMBuffer) -> [[Float]] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let capacity = Int(buffer.frameCapacity)
        return (0 ..< Int(buffer.format.channelCount)).map { channel in
            let samples = channelData[channel]
            return (0 ..< capacity).map { samples[$0] }
        }
    }

    /// Compares `[frameLength, frameCapacity)` against `reference`. Returns `(identical, changed)`.
    private static func compareTail(_ buffer: AVAudioPCMBuffer, against reference: [[Float]]) -> (identical: Bool, changed: Bool) {
        guard let channelData = buffer.floatChannelData, !reference.isEmpty else { return (false, false) }
        let start = Int(buffer.frameLength)
        let capacity = Int(buffer.frameCapacity)
        guard start < capacity else { return (true, false) }

        var identical = true
        var changed = false
        for channel in 0 ..< min(Int(buffer.format.channelCount), reference.count) {
            let samples = channelData[channel]
            for frame in start ..< capacity where frame < reference[channel].count {
                if samples[frame] != reference[channel][frame] {
                    identical = false
                    changed = true
                }
            }
        }
        return (identical, changed)
    }

    private static func tailIsAllZero(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData else { return false }
        let start = Int(buffer.frameLength)
        let capacity = Int(buffer.frameCapacity)
        guard start < capacity else { return true }
        for channel in 0 ..< Int(buffer.format.channelCount) {
            let samples = channelData[channel]
            for frame in start ..< capacity where samples[frame] != 0 {
                return false
            }
        }
        return true
    }

    // MARK: - C2 — storage reuse

    static func experimentC2(url: URL, fixture: String, capacity: AVAudioFrameCount = 4096) -> BufferLifetimeObservation {
        var observation = BufferLifetimeObservation(fixture: fixture)

        do {
            // — Addresses: one buffer across two reads —
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
                observation.error = "AVAudioPCMBuffer returned nil"
                return observation
            }

            try file.read(into: buffer)
            let first = addresses(of: buffer, readIndex: 0)
            try file.read(into: buffer)
            let second = addresses(of: buffer, readIndex: 1)
            observation.firstRead = first
            observation.secondRead = second
            observation.sameBufferAddressesStableAcrossReads =
                first.floatChannelDataAddresses == second.floatChannelDataAddresses
                    && first.audioBufferDataAddresses == second.audioBufferDataAddresses
            observation.floatChannelDataMatchesAudioBufferData =
                first.floatChannelDataAddresses == first.audioBufferDataAddresses

            // — Addresses: two distinct buffers alive at the same time —
            guard
                let bufferA = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity),
                let bufferB = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity)
            else {
                observation.error = "AVAudioPCMBuffer returned nil while allocating the distinct pair"
                return observation
            }
            let addressesA = addresses(of: bufferA, readIndex: -1).audioBufferDataAddresses
            let addressesB = addresses(of: bufferB, readIndex: -1).audioBufferDataAddresses
            observation.distinctBufferAAddresses = addressesA
            observation.distinctBufferBAddresses = addressesB
            observation.distinctBuffersHaveDistinctStorage = Set(addressesA).isDisjoint(with: Set(addressesB))

            // — Condition 1: one buffer reused, nothing wiped —
            let file1 = try AVAudioFile(forReading: url)
            guard let reused = AVAudioPCMBuffer(pcmFormat: file1.processingFormat, frameCapacity: capacity) else {
                return observation
            }
            var identicalAtShortRead: Bool?
            while file1.framePosition < file1.length {
                let before = snapshot(reused)
                try file1.read(into: reused)
                if reused.frameLength == 0 {
                    break
                }
                if reused.frameLength < reused.frameCapacity {
                    identicalAtShortRead = compareTail(reused, against: before).identical
                }
            }
            observation.reusedNoWipe_tailIdenticalToPreReadContents = identicalAtShortRead

            // — Condition 2: one buffer reused, wiped with the sentinel before every read —
            let file2 = try AVAudioFile(forReading: url)
            guard let wiped = AVAudioPCMBuffer(pcmFormat: file2.processingFormat, frameCapacity: capacity) else {
                return observation
            }
            var modifiedAtShortRead: Bool?
            while file2.framePosition < file2.length {
                fill(wiped, with: sentinel)
                let before = snapshot(wiped)
                try file2.read(into: wiped)
                if wiped.frameLength == 0 {
                    break
                }
                if wiped.frameLength < wiped.frameCapacity {
                    modifiedAtShortRead = compareTail(wiped, against: before).changed
                }
            }
            observation.reusedWiped_tailModified = modifiedAtShortRead

            // — Condition 3: a brand-new buffer for every read, nothing wiped —
            let file3 = try AVAudioFile(forReading: url)
            var previousContents: [[Float]] = []
            var perReadAddresses: [[UInt]] = []
            var addressReused = false
            var freshAllZero: Bool?
            var freshIdentical: Bool?

            while file3.framePosition < file3.length {
                guard let fresh = AVAudioPCMBuffer(pcmFormat: file3.processingFormat, frameCapacity: capacity) else { break }
                let freshAddresses = addresses(of: fresh, readIndex: perReadAddresses.count).audioBufferDataAddresses
                if perReadAddresses.contains(freshAddresses) {
                    addressReused = true
                }
                if perReadAddresses.count < 4 {
                    perReadAddresses.append(freshAddresses)
                }

                try file3.read(into: fresh)
                if fresh.frameLength == 0 {
                    break
                }

                if fresh.frameLength < fresh.frameCapacity {
                    freshAllZero = tailIsAllZero(fresh)
                    if !previousContents.isEmpty {
                        freshIdentical = compareTail(fresh, against: previousContents).identical
                    }
                }
                previousContents = snapshot(fresh)
            }

            observation.fresh_tailAllZero = freshAllZero
            observation.fresh_tailIdenticalToPreviousReadContents = freshIdentical
            observation.fresh_storageAddressReusedAcrossReads = addressReused
            observation.fresh_addressesPerRead = perReadAddresses
        } catch {
            observation.error = Describe.error(error)
        }

        return observation
    }

    // MARK: - C3 — capacity sweep

    static func experimentC3(url: URL, fixture: String, capacity: AVAudioFrameCount) -> ChunkSizeObservation {
        var observation = ChunkSizeObservation(fixture: fixture, capacity: capacity)

        do {
            // Sentinel pass.
            let file = try AVAudioFile(forReading: url)
            observation.declaredLength = file.length
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
                observation.error = "AVAudioPCMBuffer returned nil"
                return observation
            }

            var reads = 0
            var total: Int64 = 0
            var minimum = UInt32.max
            var maximum: UInt32 = 0
            var shortBeforeLast = 0
            var lastFrames: UInt32?
            var tailExisted = false
            var wipedModified = false
            var previousWasShort = false

            while file.framePosition < file.length {
                fill(buffer, with: sentinel)
                let before = snapshot(buffer)
                try file.read(into: buffer)
                let frames = buffer.frameLength
                if frames == 0 {
                    break
                }

                // A short read counted here is one that was short *and* was followed by another read.
                if previousWasShort {
                    shortBeforeLast += 1
                }
                previousWasShort = frames < buffer.frameCapacity

                reads += 1
                total += Int64(frames)
                minimum = Swift.min(minimum, frames)
                maximum = Swift.max(maximum, frames)
                lastFrames = frames

                if frames < buffer.frameCapacity {
                    tailExisted = true
                    if compareTail(buffer, against: before).changed {
                        wipedModified = true
                    }
                }
            }

            observation.reads = reads
            observation.totalFrames = total
            observation.minFrameLength = minimum == .max ? nil : minimum
            observation.maxFrameLength = maximum == 0 ? nil : maximum
            observation.shortReadsBeforeLast = shortBeforeLast
            observation.lastReadFrames = lastFrames
            observation.tailEverExisted = tailExisted
            observation.wiped_tailModified = tailExisted ? wipedModified : nil

            // No-wipe pass.
            let file2 = try AVAudioFile(forReading: url)
            guard let buffer2 = AVAudioPCMBuffer(pcmFormat: file2.processingFormat, frameCapacity: capacity) else {
                return observation
            }
            var identical: Bool?
            var changed: Bool?
            while file2.framePosition < file2.length {
                let before = snapshot(buffer2)
                try file2.read(into: buffer2)
                if buffer2.frameLength == 0 {
                    break
                }
                if buffer2.frameLength < buffer2.frameCapacity {
                    let result = compareTail(buffer2, against: before)
                    identical = result.identical
                    changed = result.changed
                }
            }
            observation.noWipe_tailIdenticalToPreReadContents = identical
            observation.noWipe_tailChanged = changed
        } catch {
            observation.error = Describe.error(error)
        }

        return observation
    }
}
