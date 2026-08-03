# Audio Inspector

> Native macOS forensic tool for inspecting the **real technical quality** of audio files —
> regardless of format, container, or what the metadata claims.

Audio Inspector is a native macOS app for music collectors, DJs, audiophiles, and anyone
digitizing vinyl, CDs, tapes, or other sources. You drag one or more audio files in, and it
analyzes the **signal itself** — not just the tags — to explain what evidence exists about the
source, the master, the rip, and the integrity of the file.

## The problem it solves

A file's extension tells you almost nothing about its quality. A FLAC file might be a clean CD rip,
a re-encode of a lossy MP3, a lossless wrapper around a degraded master, a great or mediocre vinyl
rip, a tape digitization, or a high-sample-rate file with no real content to justify it. Audio
Inspector looks at the decoded signal and reports **measurable facts**, **detected indicators**, and
**cautious inferences** — with an explicit confidence level for anything not directly provable.

It is a forensic instrument, **not a "quality: 83/100" scorer**. It separates evidence, inference,
and conclusion; offers alternative explanations; and refuses to assert what it cannot demonstrate —
for example:

> **Possible transcoding — medium confidence.** The file declares 320 kb/s but shows a persistent
> spectral cutoff around 16.1 kHz for most of the recording. This pattern is consistent with a
> source previously compressed at a lower bitrate, though it could also stem from the original
> master or from filtering applied during production.

It will never just say *"fake MP3."* The full philosophy is in [docs/vision.md](docs/vision.md) and
the reasoning model in [docs/analysis-methodology.md](docs/analysis-methodology.md).

**Honest limitations:** results are probabilistic, not verdicts; **FLAC (or any lossless format)
does not imply quality**; a higher sample rate/bitrate/bit depth is not automatically better; and
the app **does not replace critical listening** — it surfaces evidence to inform your judgment.

## Privacy

- **100% local processing.** No servers, no uploads, no telemetry, no external analytics.
- **Original files are never modified.** Tag writing (a future feature) will always require
  explicit confirmation.
- Files and folders are accessed only through macOS's secure mechanisms (security-scoped
  bookmarks). Paths and filenames are treated as untrusted data.

See [docs/privacy.md](docs/privacy.md).

## Platform & technology

- macOS 15+ (native, Apple Silicon and Intel), Swift 6 with Strict Concurrency, SwiftUI.
- Swift Package Manager; async/await and Structured Concurrency throughout.
- Native audio via AVFoundation / AudioToolbox / Accelerate (vDSP), with FFmpeg/FFprobe used
  behind an abstraction where it provides clear advantages. See
  [docs/adr/0003-ffmpeg-vs-native-audio-strategy.md](docs/adr/0003-ffmpeg-vs-native-audio-strategy.md).

## Architecture at a glance

Clean Architecture where **the dependency rule is a build constraint, not a convention**. The code
is one Swift package (`AudioInspectorKit`) whose layers are separate SwiftPM targets, so an
undeclared cross-layer `import` fails to compile; [`Scripts/check-boundaries.sh`](Scripts/check-boundaries.sh)
backstops it on full builds and in CI.

- **`AudioInspectorDomain`** imports nothing framework-side — pure value types + ports (protocols).
- **`AudioInspectorAnalysis`** (DSP, Accelerate) and **`AudioInspectorMedia`** (AVFoundation/
  AudioToolbox/FFmpeg) implement those ports; Media is the *only* place external processes appear.
- **Features** (SwiftUI) see only the Domain; **`AudioInspectorApp`** (a *library* composition root)
  wires the concretes via injection, and a thin Xcode macOS app target is the `@main` shell over it.

Because it's a library-only package, `swift build` / `swift test` run the whole layer from the CLI —
no extra executable needed.

Details in [docs/architecture.md](docs/architecture.md), [docs/concurrency.md](docs/concurrency.md),
and the [SignalFlow reuse audit](docs/signal-flow-reuse-audit.md) that shaped this structure.

## Project status

In active early development. Rather than embed a status line that would drift, this README points to
the live sources: [OVERVIEW.md](OVERVIEW.md) for architecture and orientation,
[docs/roadmap.md](docs/roadmap.md) for the plan, and `openspec list` / the active change under
`openspec/changes/` for current progress.

## Development

Development is **spec-driven** using [OpenSpec](https://github.com/Fission-AI/OpenSpec). Nothing
significant is implemented without an approved proposal and specification. See
[CONTRIBUTING.md](CONTRIBUTING.md) for environment requirements, the OpenSpec workflow, and how to
run tests.

## License

[MIT](LICENSE) © 2026 Donato Gómez. See [ADR-0007](docs/adr/0007-license-and-distribution.md) for the
rationale (and its coupling to the "no bundled FFmpeg" decision).
