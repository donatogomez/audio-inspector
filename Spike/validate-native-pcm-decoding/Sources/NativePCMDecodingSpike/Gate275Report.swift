import Foundation

enum Gate275Report {
    static func show(_ value: Bool?) -> String {
        value.map(String.init(describing:)) ?? "—"
    }

    static func show(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    static func show(_ value: String?) -> String {
        value ?? "—"
    }

    static func show(_ value: Double?, _ precision: Int = 6) -> String {
        value.map { String(format: "%.\(precision)f", $0) } ?? "—"
    }

    static func short(_ hash: String?) -> String {
        guard let hash else { return "—" }
        return String(hash.prefix(16)) + "…"
    }

    static func comparisons(_ comparisons: [RegionComparison], title: String) {
        print("  \(title)")
        if comparisons.isEmpty {
            print("    (no region to compare — the final chunk left no room past frameLength)")
            return
        }
        for c in comparisons {
            print("    ch\(c.channel): \(c.validCount) valid vs \(c.postCount) post")
            print("      post region all zero ........ \(c.postAllZero)")
            print("      elementwise identical ....... \(c.elementwiseIdentical)")
            print("      max abs difference .......... \(String(format: "%.8f", c.maxAbsDifference))")
            print("      Pearson correlation ......... \(show(c.correlation))")
            print("      valid  min / max / RMS ...... \(String(format: "%.6f", c.validMin)) / \(String(format: "%.6f", c.validMax)) / \(show(c.validRMS))")
            print("      post   min / max / RMS ...... \(String(format: "%.6f", c.postMin)) / \(String(format: "%.6f", c.postMax)) / \(show(c.postRMS))")
            print("      mean |Δ| inside valid ....... \(show(c.meanAbsDeltaWithinValid, 8))")
            print("      |Δ| across the boundary ..... \(show(c.boundaryDelta, 8))")
            print("      boundary / mean |Δ| ......... \(show(c.boundaryRatio, 3))")
            print("      CLASSIFICATION .............. \(c.classification)")
        }
    }

    static func determinism(_ o: DeterminismObservation) {
        print("  determinism — \(o.label)")
        if let error = o.error {
            print("    error: \(error)")
            return
        }
        for run in o.runs {
            print("    run \(run.index): \(run.postFrames) post frames, \(run.byteCount) bytes, sha256 \(run.sha256)")
        }
        print("    ALL HASHES IDENTICAL ........ \(show(o.allHashesIdentical))")
    }

    static func capacitySensitivity(_ records: [CapacitySensitivity]) {
        print("C6 — CAPACITY SENSITIVITY OF THE FINAL AAC CHUNK")
        print("")
        let header = ["cap", "lastLen", "postLen", "modified", "sha256 (first 16)", "classification"]
        let widths = [6, 8, 8, 9, 20, 46]
        print(zip(header, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " "))
        print(widths.map { String(repeating: "─", count: $0) }.joined(separator: " "))
        for r in records {
            let cells = [
                String(r.capacity),
                show(r.lastChunkFrameLength),
                show(r.postRegionFrames),
                show(r.modificationsObserved),
                short(r.sha256),
                r.classification ?? (r.postRegionFrames == 0 ? "not evaluated (no post region)" : "—"),
            ]
            print(zip(cells, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " "))
        }
        print("")
    }

    static func contentDependence(_ o: ContentDependence) {
        print("C7 — CONTENT DEPENDENCE  (two AAC files, identical structure, different audio)")
        print("")
        if let error = o.error {
            print("    error: \(error)")
            print("")
            return
        }
        print("    alpha post-region sha256 ...... \(show(o.alphaHash))")
        print("    beta  post-region sha256 ...... \(show(o.betaHash))")
        print("    HASHES EQUAL ACROSS FILES ..... \(show(o.hashesEqual))")
        print("")
        comparisons(o.alphaComparison ?? [], title: "C4 on alpha (440/660 Hz @ 0.25)")
        print("")
        comparisons(o.betaComparison ?? [], title: "C4 on beta (1000/1500 Hz @ 0.50)")
        print("")
        if let alpha = o.alphaDeterminism {
            determinism(alpha)
        }
        if let beta = o.betaDeterminism {
            determinism(beta)
        }
        print("")
    }
}
