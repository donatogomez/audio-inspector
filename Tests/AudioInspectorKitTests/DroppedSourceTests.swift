import Foundation
import Testing

import FeatureImport
@testable import AudioInspectorApp

/// The synchronous drop decision, exercised without building a SwiftUI view and without any real
/// drag: `DroppedSource.evaluate` is a pure function over `[URL]` plus the in-flight flag.
@MainActor
@Suite("App — dropped source decision")
struct DroppedSourceTests {

    // MARK: - Refusals

    @Test func anEmptyPayloadIsRefused() {
        #expect(DroppedSource.evaluate([], isInspecting: false) == .rejected(.unsupportedItem))
    }

    @Test func twoOrMoreItemsAreRefusedWholeAndTheFirstIsNeverTaken() async throws {
        try await withTemporaryDirectory { directory in
            let first = directory.appendingPathComponent("a.wav")
            let second = directory.appendingPathComponent("b.wav")
            try Data("a".utf8).write(to: first)
            try Data("b".utf8).write(to: second)

            let decision = DroppedSource.evaluate([first, second], isInspecting: false)

            #expect(decision == .rejected(.multipleItems))
            #expect(decision != .accepted(first)) // explicitly not the first item
        }
    }

    @Test func aNonLocalURLIsRefused() throws {
        let remote = try #require(URL(string: "https://example.com/song.wav"))
        #expect(DroppedSource.evaluate([remote], isInspecting: false) == .rejected(.unsupportedItem))
    }

    @Test func aDirectoryIsRefused() async throws {
        try await withTemporaryDirectory { directory in
            let folder = directory.appendingPathComponent("album", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            #expect(DroppedSource.evaluate([folder], isInspecting: false) == .rejected(.unsupportedItem))
        }
    }

    /// A positively-typed non-audio item is refused. The check is on type conformance, never on a
    /// hand-written extension list.
    @Test func anItemTheSystemTypesAsNonAudioIsRefused() async throws {
        try await withTemporaryDirectory { directory in
            let text = directory.appendingPathComponent("sleeve-notes.txt")
            try Data("not audio".utf8).write(to: text)

            #expect(DroppedSource.evaluate([text], isInspecting: false) == .rejected(.unsupportedItem))
        }
    }

    @Test func aDropIsRefusedWhileAnInspectionIsRunning() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("clip.wav")
            try writePCMFixture(to: file)

            // Being busy wins over everything else: nothing would be processed anyway.
            #expect(DroppedSource.evaluate([file], isInspecting: true) == .rejected(.inspectionInProgress))
            #expect(DroppedSource.evaluate([], isInspecting: true) == .rejected(.inspectionInProgress))
            #expect(DroppedSource.evaluate([file, file], isInspecting: true) == .rejected(.inspectionInProgress))
        }
    }

    // MARK: - Acceptance

    @Test func aSingleLocalAudioFileIsAccepted() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("clip.wav")
            try writePCMFixture(to: file)

            #expect(DroppedSource.evaluate([file], isInspecting: false) == .accepted(file))
        }
    }

    /// A file with no extension is typed by the system as generic data, which does not conform to
    /// audio, so it is refused. That matches the panel, whose `allowedContentTypes = [.audio]` would
    /// not offer it either — the two entry points agree, and neither consults a list of extensions we
    /// wrote ourselves.
    @Test func aFileTheSystemTypesAsGenericDataIsRefusedJustAsThePanelWouldHideIt() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("recording")
            try Data(repeating: 0x41, count: 64).write(to: file)

            #expect(DroppedSource.evaluate([file], isInspecting: false) == .rejected(.unsupportedItem))
        }
    }

    /// Conformance, not the literal type, is what decides: an AIFF fixture is a different concrete
    /// type from a WAV and both are accepted, so nothing here encodes a per-format allow-list.
    @Test func aDifferentAudioContainerIsAlsoAccepted() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("clip.aiff")
            try writePCMFixture(to: file)

            #expect(DroppedSource.evaluate([file], isInspecting: false) == .accepted(file))
        }
    }

    /// The observation found Finder delivers conventional path URLs, so nothing is rewritten: the URL
    /// handed on is exactly the URL received (ADR-0014).
    @Test func anAcceptedURLIsPassedThroughUnchanged() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("clip.wav")
            try writePCMFixture(to: file)

            guard case let .accepted(url) = DroppedSource.evaluate([file], isInspecting: false) else {
                Issue.record("expected the file to be accepted"); return
            }
            #expect(url == file)
            #expect(url.absoluteString == file.absoluteString)
            #expect(url.lastPathComponent == "clip.wav")
            #expect(url.pathExtension == "wav")
        }
    }
}
