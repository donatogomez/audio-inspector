import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp

/// Tests the `URL → AudioFileReference` translation. Real files in a temporary directory (resource
/// values need one), cleaned up with `defer`. The key property under test is that the reference is
/// **safe**: it carries descriptive metadata and never the location.
@Suite("App — audio file reference mapper")
struct AudioFileReferenceMapperTests {

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test func mapsNameExtensionSizeAndModificationDate() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("interview-side-a.M4A")
            try Data(repeating: 0x41, count: 1_234).write(to: url)

            let reference = AudioFileReferenceMapper.reference(for: url)

            #expect(reference.displayName == "interview-side-a.M4A")
            #expect(reference.fileExtension == "m4a") // lowercased
            #expect(reference.sizeBytes == 1_234)
            #expect(reference.modifiedAt != nil)
        }
    }

    @Test func mapsSafeSourceDescriptor() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("clip.wav")
            try Data("x".utf8).write(to: url)

            let reference = AudioFileReferenceMapper.reference(for: url)

            guard case let .userSelectedLocalFile(displayName, disclosure) = reference.source else {
                Issue.record("expected userSelectedLocalFile"); return
            }
            #expect(displayName == "clip.wav")
            #expect(disclosure == .omitted)
        }
    }

    @Test func fileWithoutExtensionHasNilExtension() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("recording")
            try Data("x".utf8).write(to: url)

            let reference = AudioFileReferenceMapper.reference(for: url)

            #expect(reference.displayName == "recording")
            #expect(reference.fileExtension == nil)
        }
    }

    @Test func unreadableMetadataBecomesNilAndNeverAborts() throws {
        try withTemporaryDirectory { directory in
            // A URL pointing at nothing: the resource values read fails, so both attributes are absent.
            let url = directory.appendingPathComponent("missing.wav")

            let reference = AudioFileReferenceMapper.reference(for: url)

            #expect(reference.displayName == "missing.wav")
            #expect(reference.fileExtension == "wav")
            #expect(reference.sizeBytes == nil) // nil, never fabricated
            #expect(reference.modifiedAt == nil)
        }
    }

    @Test func referenceNeverCarriesTheLocation() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("private-song.flac")
            try Data("x".utf8).write(to: url)

            let reference = AudioFileReferenceMapper.reference(for: url)

            // Nothing in the reference reproduces the directory it came from.
            let directoryName = directory.lastPathComponent
            #expect(!reference.displayName.contains(directoryName))
            #expect(!reference.displayName.contains("/"))
            guard case let .userSelectedLocalFile(displayName, _) = reference.source else {
                Issue.record("expected userSelectedLocalFile"); return
            }
            #expect(!displayName.contains(directoryName))
            // The type itself has no field for a path/URL/bookmark — verified structurally by the
            // domain model (AudioFileReference), so there is nowhere for a location to hide.
        }
    }
}
