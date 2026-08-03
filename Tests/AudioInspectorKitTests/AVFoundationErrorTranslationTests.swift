import AVFoundation
import Foundation
import Testing

@testable import AudioInspectorMedia
import AudioInspectorDomain

/// Task 3.7 — **error-translation** unit tests for `AVFoundationAudioFilePropertyReader`.
///
/// The whole-file (global) classifier `globalError(from:)` is exercised with **controlled in-memory
/// Apple errors** (`CocoaError`/`AVError` built directly, plus a generic `Error`) — no real files, no
/// asset loading. This is the deterministic, SDK-portable way to cover the scope-based mapping: the
/// spike's own caveat is that numeric error codes are SDK-dependent, so the productive contract is
/// validated by feeding the classifier the *bridged* error types it branches on. Assertions key on the
/// stable domain `InspectionErrorCode`, never on any localized/system message.
@Suite("Media — AVFoundation global error translation (in-memory)")
struct AVFoundationErrorTranslationTests {

    private struct UnclassifiedError: Error {}

    private func classify(_ error: some Error) -> InspectionErrorCode {
        AVFoundationAudioFilePropertyReader.globalError(from: error).code
    }

    // MARK: - CocoaError scope mapping

    @Test func permissionDeniedMapsToFileAccessDenied() {
        #expect(classify(CocoaError(.fileReadNoPermission)) == .fileAccessDenied)
    }

    @Test func corruptFileMapsToFileUnreadable() {
        #expect(classify(CocoaError(.fileReadCorruptFile)) == .fileUnreadable)
    }

    @Test func missingFileFallsBackToFileOpenFailed() {
        // A missing file could not be *opened*; it is not over-claimed as unreadable media.
        #expect(classify(CocoaError(.fileReadNoSuchFile)) == .fileOpenFailed)
    }

    // MARK: - AVError scope mapping (unrecognizable / corrupt media → unreadable)

    @Test(arguments: [
        AVError.Code.fileFormatNotRecognized,
        .failedToParse,
        .undecodableMediaData,
    ])
    func unrecognizableMediaMapsToFileUnreadable(code: AVError.Code) {
        #expect(classify(AVError(code)) == .fileUnreadable)
    }

    @Test func unknownAVErrorFallsBackToFileOpenFailed() {
        #expect(classify(AVError(.unknown)) == .fileOpenFailed)
    }

    // MARK: - Unclassified / non-Apple errors → stable fallback

    @Test func genericErrorFallsBackToFileOpenFailed() {
        #expect(classify(UnclassifiedError()) == .fileOpenFailed)
    }

    // MARK: - Message is descriptive only, never a leaked system string

    @Test func classifiedErrorCarriesADeterministicNonEmptyMessage() {
        // The message exists and is stable, but it is never the assertion's identity (that is the code).
        let error = AVFoundationAudioFilePropertyReader.globalError(from: CocoaError(.fileReadNoPermission))
        #expect(error.code == .fileAccessDenied)
        #expect(!error.message.isEmpty)
    }
}
