import Foundation

enum Gate25Report {
    static func show(_ value: Bool?) -> String {
        value.map(String.init(describing:)) ?? "—"
    }

    static func show(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    static func show(_ value: Int64?) -> String {
        value.map(String.init) ?? "—"
    }

    static func show(_ value: UInt32?) -> String {
        value.map(String.init) ?? "—"
    }

    static func show(_ value: String?) -> String {
        value ?? "—"
    }

    static func hex(_ addresses: [UInt]?) -> String {
        addresses.map { $0.map { String(format: "0x%012lX", $0) }.joined(separator: " ") } ?? "—"
    }

    static func bufferLifetime(_ observations: [BufferLifetimeObservation]) {
        print("C2 — STORAGE REUSE  (capacity 4096; addresses are of this run only)")
        print("")
        for o in observations {
            print("── \(o.fixture) " + String(repeating: "─", count: max(0, 56 - o.fixture.count)))
            print("  addresses")
            print("    read 0 floatChannelData ....... \(hex(o.firstRead?.floatChannelDataAddresses))")
            print("    read 0 AudioBuffer.mData ...... \(hex(o.firstRead?.audioBufferDataAddresses))")
            print("    read 0 capacity / length ...... \(show(o.firstRead?.frameCapacity)) / \(show(o.firstRead?.frameLength))")
            print("    read 1 floatChannelData ....... \(hex(o.secondRead?.floatChannelDataAddresses))")
            print("    read 1 AudioBuffer.mData ...... \(hex(o.secondRead?.audioBufferDataAddresses))")
            print("    read 1 capacity / length ...... \(show(o.secondRead?.frameCapacity)) / \(show(o.secondRead?.frameLength))")
            print("    same buffer, addresses stable . \(show(o.sameBufferAddressesStableAcrossReads))")
            print("    floatChannelData == mData ..... \(show(o.floatChannelDataMatchesAudioBufferData))")
            print("    distinct buffer A ............. \(hex(o.distinctBufferAAddresses))")
            print("    distinct buffer B ............. \(hex(o.distinctBufferBAddresses))")
            print("    distinct buffers, disjoint .... \(show(o.distinctBuffersHaveDistinctStorage))")
            print("  condition 1 — one buffer reused, nothing wiped")
            print("    tail identical to pre-read .... \(show(o.reusedNoWipe_tailIdenticalToPreReadContents))")
            print("  condition 2 — one buffer reused, wiped before every read")
            print("    tail modified ................. \(show(o.reusedWiped_tailModified))")
            print("  condition 3 — a new buffer for every read, nothing wiped")
            print("    tail all zero ................. \(show(o.fresh_tailAllZero))")
            print("    tail identical to previous read \(show(o.fresh_tailIdenticalToPreviousReadContents))")
            print("    storage address seen before ... \(show(o.fresh_storageAddressReusedAcrossReads))")
            if let perRead = o.fresh_addressesPerRead {
                for (index, addresses) in perRead.enumerated() {
                    print("    fresh read \(index) mData ........... \(hex(addresses))")
                }
            }
            print("    error ......................... \(show(o.error))")
            print("")
        }
    }

    static func chunkSizes(_ observations: [ChunkSizeObservation]) {
        print("C3 — CAPACITY SWEEP  (functional behaviour only; no timing)")
        print("")
        let header = ["fixture", "cap", "reads", "total", "minLen", "maxLen", "shortMid", "lastLen", "tail?", "wiped:mod", "noWipe:same", "noWipe:chg"]
        let widths = [8, 5, 6, 7, 7, 7, 9, 8, 6, 10, 12, 11]
        print(zip(header, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " "))
        print(widths.map { String(repeating: "─", count: $0) }.joined(separator: " "))
        for o in observations {
            let cells = [
                o.fixture,
                String(o.capacity),
                show(o.reads),
                show(o.totalFrames),
                show(o.minFrameLength),
                show(o.maxFrameLength),
                show(o.shortReadsBeforeLast),
                show(o.lastReadFrames),
                show(o.tailEverExisted),
                show(o.wiped_tailModified),
                show(o.noWipe_tailIdenticalToPreReadContents),
                show(o.noWipe_tailChanged),
            ]
            print(zip(cells, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " "))
        }
        print("")
        print("  cap        = frameCapacity requested")
        print("  shortMid   = reads that returned fewer frames than capacity AND were followed by another read")
        print("  tail?      = a region [frameLength, frameCapacity) existed on at least one read")
        print("  wiped:mod  = with the whole capacity overwritten before each read, the tail differed afterwards")
        print("  noWipe:same= without wiping, the tail still held exactly its pre-read contents")
        print("  noWipe:chg = without wiping, part of the tail differed from its pre-read contents")
        print("")
    }
}
