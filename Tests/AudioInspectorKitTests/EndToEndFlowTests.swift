import AVFoundation
import CryptoKit
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorTesting
import FeatureImport
@testable import AudioInspectorApp
@testable import FeatureAnalysis

/// The end-to-end validation of the MVP slice (task 7.1) together with the source-integrity guarantee
/// (task 7.2's first half).
///
/// One run walks the **entire production chain**: a real PCM file on disk → the safe reference →
/// the real AVFoundation reader → the use case → the report held by `ImportFlowModel` → the
/// presentation formatter → the real JSON exporter → a real write to a different file → the bytes
/// read back and decoded with `Codable`.
///
/// The **only** doubles are the two points where a human would act, plus the two envelope inputs that
/// must be deterministic: the source picker, the destination picker, the clock, and the generator
/// identity. `NSOpenPanel` and `NSSavePanel` are never opened; the sandbox powerbox and the visual
/// rendering are out of reach from SwiftPM and are covered by `docs/manual-validation-mvp.md`.
@MainActor
@Suite("End-to-end — inspect a real file and export its report")
struct EndToEndFlowTests {

    /// Descriptive attributes captured straight from the filesystem, to compare before and after.
    /// Access time is deliberately **not** captured: reading a file legitimately updates it.
    private struct SourceAttributes: Equatable {
        let sizeBytes: Int?
        let modifiedAt: Date?
    }

    private func attributes(of url: URL) throws -> SourceAttributes {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return SourceAttributes(sizeBytes: values.fileSize, modifiedAt: values.contentModificationDate)
    }

    /// SHA-256 over every byte of the file, using the platform's own crypto — no subprocess, no
    /// external tool. `CryptoKit` is used here in tests only; production never hashes anything.
    private func sha256(of url: URL) throws -> SHA256Digest {
        SHA256.hash(data: try Data(contentsOf: url))
    }

    @Test func inspectsAPCMFileExportsItsReportAndLeavesTheSourceUntouched() async throws {
        try await withTemporaryDirectory { directory in
            // 1. A real audio file on disk.
            let source = directory.appendingPathComponent("fixture.wav")
            try writePCMFixture(to: source)

            // 7.2 — the source as it stands before anything touches it.
            let hashBefore = try sha256(of: source)
            let attributesBefore = try attributes(of: source)

            // 2–6. Selection seam → coordinator (mapper + real reader + use case) → flow model.
            let inspection = SourceInspectionCoordinator(chooseSource: { source })
            let flow = ImportFlowModel(action: { onUpdate in await inspection.inspect(onUpdate: onUpdate) })
            await flow.selectAndInspect()

                        guard case let .report(presentation) = flow.state else {
                Issue.record("expected the flow to end in .report, got \(flow.state)"); return
            }
            let report = presentation.report

            // The waveform travelled the same pipeline, beside the report and never inside it: this run
            // uses the production generator, so a real second read of the same file happened inside the
            // one access window.
            guard case let .available(envelope) = presentation.waveform else {
                Issue.record("expected an available waveform, got \(presentation.waveform)"); return
            }
            #expect(envelope.channelCount == 1, "the envelope describes the file the report describes")
            #expect(envelope.frameCount > 0)
            #expect(envelope.buckets.count == min(2_048, envelope.frameCount))
            // It reaches the surface that draws it, as the state that draws it.
            #expect(RootView.waveformPresentation(for: presentation.waveform) == .envelope(envelope))

            // The spectrogram travelled the same pipeline, beside the report and beside the waveform.
            // This run uses the production decoder and the production accumulator, so a real STFT over
            // a real file happened inside the same access window.
            guard case let .available(spectrogram) = presentation.spectrogram else {
                Issue.record("expected an available spectrogram, got \(presentation.spectrogram)"); return
            }
            #expect(spectrogram.sampleRate == 44_100, "the model describes the file the report describes")
            #expect(spectrogram.channelCount == 1)
            #expect(spectrogram.frameCount > 0)
            #expect(spectrogram.columnCount > 0)
            #expect(spectrogram.bandCount == 512)
            #expect(spectrogram.values.count == spectrogram.columnCount * spectrogram.bandCount)
            #expect(spectrogram.values.allSatisfy { $0.isFinite && $0 >= Spectrogram.floorDecibels })
            #expect(spectrogram.nyquist == 22_050)
            // It reaches the surface that draws it, as the state that draws it.
            #expect(RootView.spectrogramPresentation(for: presentation.spectrogram) == .model(spectrogram))

            // The report describes the selected file, with no location anywhere in it.
            #expect(report.file.displayName == "fixture.wav")
            #expect(report.file.fileExtension == "wav")
            #expect(report.file.sizeBytes == attributesBefore.sizeBytes)
            #expect(report.file.modifiedAt != nil)

            // The PCM facts the reader is validated to produce (spike 0031).
            #expect(report.properties.sampleRate == .available(44_100))
            #expect(report.properties.channelCount == .available(1))
            #expect(report.properties.bitDepth == .available(16))
            #expect(report.properties.codec == .available("lpcm"))
            guard case let .available(seconds) = report.properties.duration else {
                Issue.record("expected an available duration, got \(report.properties.duration)"); return
            }
            #expect(seconds > 0)

            // 7. The report is presentable: the nine rows `ReportView` renders.
            let displays = ReportPropertyFormatter.displays(for: report.properties)
            #expect(displays.count == 9)
            // Every row is well formed: nothing failed to read on a fixture we generated ourselves.
            #expect(displays.allSatisfy { $0.state != .couldNotBeRead })
            // Readable value, with the exact figure preserved beside it.
            #expect(displays.first { $0.name == "Sample rate" }?.value == "44.1 kHz")
            #expect(displays.first { $0.name == "Sample rate" }?.detail == "44,100 Hz")
            // The codec token `lpcm` is now named, with the token preserved as detail.
            #expect(displays.first { $0.name == "Codec" }?.value == "Linear PCM")
            #expect(displays.first { $0.name == "Codec" }?.detail == "lpcm")
            // A real file with a real, known size and a confirmed duration: the calculated average
            // bitrate is computable for real here, not just in the controlled pure-mapping tests.
            guard case let .uncertain(averageValue, _) = report.properties.averageFileBitrate else {
                Issue.record("expected an uncertain averageFileBitrate, got \(report.properties.averageFileBitrate)"); return
            }
            let sizeBytes = try #require(report.file.sizeBytes)
            #expect(averageValue == Int((Double(sizeBytes) * 8.0 / seconds).rounded(.toNearestOrAwayFromZero)))

            // 8–10. The same report, exported for real to a *different* file.
            let destination = directory.appendingPathComponent("out.json")
            #expect(destination != source)
            var suggestedName: String?
            let exportCoordinator = ReportExportCoordinator(
                exporter: JSONReportExporter(generator: fixedGenerator, now: { fixedNow }),
                chooseDestination: { name in suggestedName = name; return destination }
            )
            let exportModel = ReportExportModel(action: { report, measurements in
                await exportCoordinator.export(report, measurements: measurements)
            })
            await exportModel.export(report, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))

            #expect(exportModel.phase == .succeeded)
            #expect(suggestedName == "fixture-inspection.json")

            // Exporting neither recalculates nor mutates the report the UI holds, and it leaves
            // whatever became of the waveform beside it untouched.
            #expect(flow.state == .report(presentation))

            // 11. Read the bytes back and decode them with `Codable` only.
            let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: destination))

            // 12. The document is coherent with *that* report.
            #expect(json["schemaVersion"]?.int == 1)
            #expect(json["generatedAt"]?.string == "2026-08-03T12:00:00Z")
            #expect(json["generator"]?["name"]?.string == "Audio Inspector")
            #expect(json["generator"]?["version"]?.string == "0.1.0")

            let inspectedFile = try #require(json["inspectedFile"])
            #expect(inspectedFile["name"]?.string == report.file.displayName)
            #expect(inspectedFile["fileExtension"]?.string == "wav")
            #expect(inspectedFile["sizeBytes"]?.int == report.file.sizeBytes)
            #expect(inspectedFile["source"]?["kind"]?.string == "userSelectedLocalFile")
            #expect(inspectedFile["source"]?["locationDisclosure"]?.string == "omitted")

            let technical = try #require(json["technicalProperties"])
            #expect(try #require(technical.keys) == [
                "container", "duration", "sampleRate", "channelCount",
                "bitDepth", "codec", "declaredBitrate", "estimatedBitrate", "averageFileBitrate",
            ])
            #expect(technical["sampleRate"]?["value"]?.int == 44_100)
            #expect(technical["codec"]?["value"]?.string == "lpcm")

            // Warnings and status come from the report unchanged — the exporter derives nothing.
            let warnings = try #require(json["warnings"]?.array)
            #expect(warnings.count == report.warnings.count)
            #expect(json["inspectionStatus"]?["state"]?.string == wireState(of: report.status))

            // Privacy: no location can appear anywhere, and the ephemeral id never leaks.
            let forbidden: Set<String> = [
                "path", "url", "fileURL", "absolutePath", "bookmark", "securityScopedBookmark",
                "parentDirectory", "directory", "location", "bookmarkData", "id",
            ]
            #expect(allKeys(json).isDisjoint(with: forbidden))
            let text = try #require(String(data: try Data(contentsOf: destination), encoding: .utf8))
            #expect(!text.contains(directory.path))
            #expect(!text.contains(directory.lastPathComponent))
            #expect(!text.contains(report.file.id.uuidString))

            // The directory holds exactly the source and its export — nothing else was written.
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            #expect(contents == ["fixture.wav", "out.json"])

            // 7.2 — the source is byte-identical after inspecting *and* exporting.
            #expect(try sha256(of: source) == hashBefore)
            #expect(try attributes(of: source) == attributesBefore)
        }
    }

    /// The same walk, for a file whose samples cannot be read.
    ///
    /// The point is not that the waveform is missing — that is scripted — but that **nothing else
    /// moves when it is**: the same pipeline runs end to end, the report is complete, the export
    /// succeeds and the document written to disk is byte-identical to the one the run above produced.
    /// The only substitution beyond the two panels is the **decoding** port; the property reader, the
    /// use case, the flow model, the exporter and the write are all real.
    ///
    /// Since ADR-0021 the waveform settles from the shared read, so a file whose samples cannot be read
    /// takes **every** sample-based analysis with it. That widens what this walk demonstrates rather
    /// than narrowing it: none of the four reaches the report, the warnings, the status or a single byte
    /// of the export.
    @Test func theSamePipelineRunsAndExportsIdenticallyWhenNoWaveformCanBeProduced() async throws {
        try await withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("fixture.wav")
            try writePCMFixture(to: source)
            let hashBefore = try sha256(of: source)

            @MainActor
            func run(decoder: FakeAudioDecoding?) async throws -> (InspectionPresentation, Data) {
                let inspection = decoder.map { scripted in
                    SourceInspectionCoordinator(chooseSource: { source }, makeDecoder: { _ in scripted })
                } ?? SourceInspectionCoordinator(chooseSource: { source })
                let flow = ImportFlowModel(action: { onUpdate in await inspection.inspect(onUpdate: onUpdate) })
                await flow.selectAndInspect()

                guard case let .report(presentation) = flow.state else {
                    throw FlowDidNotProduceAReport()
                }
                let destination = directory.appendingPathComponent("out-\(UUID().uuidString).json")
                let exportCoordinator = ReportExportCoordinator(
                    exporter: JSONReportExporter(generator: fixedGenerator, now: { fixedNow }),
                    chooseDestination: { _ in destination }
                )
                let exportModel = ReportExportModel(action: { report, measurements in
                await exportCoordinator.export(report, measurements: measurements)
            })
                await exportModel.export(presentation.report, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))
                #expect(exportModel.phase == .succeeded)

                return (presentation, try Data(contentsOf: destination))
            }

            let (withWaveform, documentWithWaveform) = try await run(decoder: nil)
            let (withoutWaveform, documentWithoutWaveform) = try await run(decoder: FakeAudioDecoding(.absent))

            // Both walks produced a real, complete report, and the two really are different runs.
            guard case .available = withWaveform.waveform else {
                Issue.record("expected a real envelope, got \(withWaveform.waveform)"); return
            }
            #expect(withoutWaveform.waveform == .unavailable)
            #expect(withoutWaveform.report.properties.sampleRate == .available(44_100))
            #expect(withoutWaveform.report.properties.channelCount == .available(1))

            // The report says the same thing either way…
            #expect(withoutWaveform.report.properties == withWaveform.report.properties)
            #expect(withoutWaveform.report.warnings == withWaveform.report.warnings)
            #expect(withoutWaveform.report.status == withWaveform.report.status)

            // …and so does every byte written to disk.
            #expect(documentWithoutWaveform == documentWithWaveform)

            // The surface is told the truth about the absence rather than shown an empty drawing.
            #expect(RootView.waveformPresentation(for: withoutWaveform.waveform) == .absent)

            // And neither walk touched the source.
            #expect(try sha256(of: source) == hashBefore)
        }
    }

    /// The same walk again, this time for the spectrogram: **present in one run, absent in the other,
    /// and nothing else moves.**
    ///
    /// The run with a spectrogram uses the **production** decoder and accumulator over a real file, so
    /// the model is genuinely produced rather than scripted; the run without substitutes only the
    /// decoding port. The property reader, the use case, the flow model, the exporter and the write are
    /// real in both. Every byte written to disk must be identical, because the export has never had a
    /// route to the spectrogram at all.
    @Test func theSamePipelineRunsAndExportsIdenticallyWhenNoSpectrogramCanBeProduced() async throws {
        try await withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("fixture.wav")
            try writePCMFixture(to: source)
            let hashBefore = try sha256(of: source)

            @MainActor
            func run(decoder: FakeAudioDecoding?) async throws -> (InspectionPresentation, Data) {
                let inspection = decoder.map { scripted in
                    SourceInspectionCoordinator(chooseSource: { source }, makeDecoder: { _ in scripted })
                } ?? SourceInspectionCoordinator(chooseSource: { source })
                let flow = ImportFlowModel(action: { onUpdate in await inspection.inspect(onUpdate: onUpdate) })
                await flow.selectAndInspect()

                guard case let .report(presentation) = flow.state else {
                    throw FlowDidNotProduceAReport()
                }
                let destination = directory.appendingPathComponent("out-\(UUID().uuidString).json")
                let exportCoordinator = ReportExportCoordinator(
                    exporter: JSONReportExporter(generator: fixedGenerator, now: { fixedNow }),
                    chooseDestination: { _ in destination }
                )
                let exportModel = ReportExportModel(action: { report, measurements in
                await exportCoordinator.export(report, measurements: measurements)
            })
                await exportModel.export(presentation.report, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))
                #expect(exportModel.phase == .succeeded)

                return (presentation, try Data(contentsOf: destination))
            }

            let (withSpectrogram, documentWithSpectrogram) = try await run(decoder: nil)
            let (withoutSpectrogram, documentWithoutSpectrogram) = try await run(decoder: FakeAudioDecoding(.absent))

            // Both walks produced a real, complete report — and the two really are different runs.
            guard case let .available(model) = withSpectrogram.spectrogram else {
                Issue.record("expected a real model, got \(withSpectrogram.spectrogram)"); return
            }
            #expect(model.columnCount > 0)
            #expect(withoutSpectrogram.spectrogram == .unavailable)

            // The report says the same thing either way…
            #expect(withoutSpectrogram.report.properties == withSpectrogram.report.properties)
            #expect(withoutSpectrogram.report.warnings == withSpectrogram.report.warnings)
            #expect(withoutSpectrogram.report.status == withSpectrogram.report.status)

            // …the waveform settles from the **same** read since ADR-0021, so it shares the
            // spectrogram's fate rather than being untouched by it. What must not move is the report and
            // the document, which is what the two assertions above and the one below pin.
            #expect(withoutSpectrogram.waveform == .unavailable)

            // …and so does every byte written to disk.
            #expect(documentWithoutSpectrogram == documentWithSpectrogram)

            // The surface is told the truth about the absence rather than shown an empty drawing.
            #expect(RootView.spectrogramPresentation(for: withoutSpectrogram.spectrogram) == .absent)

            // And neither walk touched the source.
            #expect(try sha256(of: source) == hashBefore)
        }
    }

    /// **The real path that was never exercised before.** Every existing export test in this suite —
    /// and every one of `JSONReportExportMeasurementsTests` — either passes `signalLevelMetrics: nil`
    /// explicitly or constructs a `SignalLevelMetrics` fixture by hand and hands it straight to the
    /// exporter. None of them walk the actual production sequence: a real file, decoded for real by the
    /// real `SignalLevelMetricsGeneration`, settling into `InspectionPresentation.signalLevelMetrics`,
    /// extracted from it through the production seam `ExportableMeasurements` (`.available` unwrapped,
    /// everything else `nil`), and only then exported. A manual validation pass found that
    /// gap by hand; this closes it permanently.
    @Test func theRealSignalLevelMetricsPathReachesTheExportedDocument() async throws {
        try await withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("fixture.wav")
            try writePCMFixture(to: source)

            // 1–6. The full production sequence: selection → coordinator → real reader, real decoder,
            // real SignalLevelMetricsGeneration → flow model. No port is scripted.
            let inspection = SourceInspectionCoordinator(chooseSource: { source })
            let flow = ImportFlowModel(action: { onUpdate in await inspection.inspect(onUpdate: onUpdate) })
            await flow.selectAndInspect()

            guard case let .report(presentation) = flow.state else {
                Issue.record("expected the flow to end in .report, got \(flow.state)"); return
            }

            // The metrics really were produced — this run is exercising something real, not proving
            // nothing by exporting an absence.
            guard case let .available(metrics) = presentation.signalLevelMetrics else {
                Issue.record("expected available signal level metrics, got \(presentation.signalLevelMetrics)")
                return
            }
            #expect(metrics.channels.count == 1)
            #expect(metrics.overallPeakSample != nil)

            let destination = directory.appendingPathComponent("out.json")
            let exportCoordinator = ReportExportCoordinator(
                exporter: JSONReportExporter(generator: fixedGenerator, now: { fixedNow }),
                chooseDestination: { _ in destination }
            )
            let exportModel = ReportExportModel(action: { report, measurements in
                await exportCoordinator.export(report, measurements: measurements)
            })

            // The composition root's own translation, `RootView.signalLevelMetricsPresentation(for:)`,
            // then the same extraction the button performs — the two seams between the flow's state and
            // what actually gets exported.
            // **The production seam itself**, not a copy of it: the collapse the export button performs
            // lives in `ExportableMeasurements`, so this walks the real path rather than one that
            // happens to agree with it.
            let toExport = ExportableMeasurements.value(
                of: RootView.signalLevelMetricsPresentation(for: presentation.signalLevelMetrics)
            )
            await exportModel.export(presentation.report, measurements: ReportMeasurements(signalLevelMetrics: toExport, truePeak: nil, loudness: nil, programmeBandwidth: nil))
            #expect(exportModel.phase == .succeeded)

            let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: destination))
            let signalLevels = try #require(json["measurements"]?["signalLevels"], "measurements never reached the export")
            #expect(signalLevels["overall"]?["peakSample"]?.double == Double(try #require(metrics.overallPeakSample)))
            #expect(signalLevels["channels"]?.array?.count == 1)
        }
    }

    /// The same walk for **true peak**, and for the same reason: the unit tests above export a
    /// hand-built measurement, so on their own they would pass even if the real value never left the
    /// flow. This drives the production sequence — real file, real decode, real shared read producing a
    /// real `TruePeakMeasurement` — through the composition root's own translation and the exact
    /// extraction the export button performs, and asserts the number that arrives in the document is
    /// the one that was measured.
    @Test func theRealTruePeakPathReachesTheExportedDocument() async throws {
        try await withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("fixture.wav")
            try writePCMFixture(to: source)

            let inspection = SourceInspectionCoordinator(chooseSource: { source })
            let flow = ImportFlowModel(action: { onUpdate in await inspection.inspect(onUpdate: onUpdate) })
            await flow.selectAndInspect()

            guard case let .report(presentation) = flow.state else {
                Issue.record("expected the flow to end in .report, got \(flow.state)"); return
            }
            guard case let .available(measured) = presentation.truePeak else {
                Issue.record("expected an available true peak, got \(presentation.truePeak)"); return
            }
            // Something real was measured, so exporting it proves something.
            #expect(measured.channels.count == 1)
            let measuredOverall = try #require(measured.overallTruePeak)

            let destination = directory.appendingPathComponent("out-true-peak.json")
            let exportCoordinator = ReportExportCoordinator(
                exporter: JSONReportExporter(generator: fixedGenerator, now: { fixedNow }),
                chooseDestination: { _ in destination }
            )
            let exportModel = ReportExportModel(action: { report, measurements in
                await exportCoordinator.export(report, measurements: measurements)
            })

            let toExport = ExportableMeasurements.value(
                of: RootView.truePeakPresentation(for: presentation.truePeak)
            )
            await exportModel.export(presentation.report, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: toExport, loudness: nil, programmeBandwidth: nil))
            #expect(exportModel.phase == .succeeded)

            let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: destination))
            let truePeak = try #require(json["measurements"]?["truePeak"], "the true peak never reached the export")
            #expect(truePeak["overall"]?.double == Double(measuredOverall), "the exported value is not the measured one")
            #expect(truePeak["channels"]?.array?.count == 1)
            #expect(truePeak["channels"]?.array?[0]["sampleCount"]?.int == measured.channels[0].sampleCount)
            #expect(truePeak["method"]?["oversamplingFactor"]?.int == 8)
            #expect(truePeak["method"]?["filter"]?.string == "polyphase_fir_v1")
            // Linear on the wire: the same number reads as a dBTP figure on screen and must not here.
            #expect(try #require(truePeak["overall"]?.double) > 0)
        }
    }

    /// The same walk for **integrated loudness**, parameterised by sample rate — and it is the one
    /// analysis whose end-to-end test has to be, because the weighting's provenance changes with the
    /// rate while nothing else does.
    ///
    /// 48 kHz is where BS.1770-5's coefficients are published and transcribed; 44.1 kHz and 96 kHz use
    /// coefficients this project derived to reproduce that response. **The document must say which one
    /// actually ran**, and it must say it because the measurement carried it — not because the mapper
    /// inferred it from a sample rate it never sees.
    ///
    /// The fixture is a full second, well past the 400 ms a gating block needs, at an amplitude that
    /// clears the absolute gate: a shorter or quieter file would be `unavailable`, which is a correct
    /// answer but not the one this test is about.
    @Test(arguments: [
        (44_100.0, LoudnessWeightingIdentifier.derivedFrom48kHz),
        (48_000.0, LoudnessWeightingIdentifier.publishedAt48kHz),
        (96_000.0, LoudnessWeightingIdentifier.derivedFrom48kHz),
    ])
    func theRealLoudnessPathReachesTheExportedDocument(
        rate: Double, expectedWeighting: LoudnessWeightingIdentifier
    ) async throws {
        try await withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("loudness-fixture.wav")
            try writeAudioFixture(
                AudioFixtureSpec(
                    name: "loudness-fixture",
                    format: .wav,
                    signal: .sine(frequency: 997, amplitude: 0.5),
                    sampleRate: rate,
                    channels: 2,
                    frames: AVAudioFrameCount(rate)
                ),
                to: source
            )

            let inspection = SourceInspectionCoordinator(chooseSource: { source })
            let flow = ImportFlowModel(action: { onUpdate in await inspection.inspect(onUpdate: onUpdate) })
            await flow.selectAndInspect()

            guard case let .report(presentation) = flow.state else {
                Issue.record("expected the flow to end in .report, got \(flow.state)"); return
            }
            guard case let .available(measured) = presentation.loudness else {
                Issue.record("expected an available loudness at \(rate) Hz, got \(presentation.loudness)"); return
            }
            // Something real was measured, and the weighting is the one this rate calls for.
            #expect(measured.integratedLoudness.isFinite)
            #expect(measured.method.weighting == expectedWeighting)
            #expect(measured.method.algorithm == .integratedBS1770v1)

            let destination = directory.appendingPathComponent("out-loudness.json")
            let exportCoordinator = ReportExportCoordinator(
                exporter: JSONReportExporter(generator: fixedGenerator, now: { fixedNow }),
                chooseDestination: { _ in destination }
            )
            let exportModel = ReportExportModel(action: { report, measurements in
                await exportCoordinator.export(report, measurements: measurements)
            })

            let toExport = ExportableMeasurements.value(
                of: RootView.loudnessPresentation(for: presentation.loudness)
            )
            await exportModel.export(
                presentation.report,
                measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: toExport, programmeBandwidth: nil)
                )
            #expect(exportModel.phase == .succeeded)

            let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: destination))
            let exported = try #require(
                json["measurements"]?["integratedLoudness"], "the loudness never reached the export"
            )
            // **Exactly** the accumulator's own number — not a rounded one, and not a converted one.
            #expect(exported["value"]?.double == measured.integratedLoudness)
            #expect(exported["method"]?["weighting"]?.string == expectedWeighting.rawValue)
            #expect(exported["method"]?["algorithm"]?.string == "itu_r_bs1770_5_integrated_v1")
            // The one decimal belongs to the screen, and the two must not agree by accident.
            #expect(
                HumanFormat.loudnessFullScale(measured.integratedLoudness)
                    == "\(exported["value"]!.double!.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)).locale(HumanFormat.locale))) LUFS"
            )
        }
    }

    private struct FlowDidNotProduceAReport: Error {}

    /// The wire token for a domain status, so the JSON is compared against the report rather than
    /// against a hard-coded expectation.
    private func wireState(of status: InspectionStatus) -> String {
        switch status {
        case .completed: "completed"
        case .partial: "partial"
        case .failed: "failed"
        }
    }
}
