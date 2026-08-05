# Architecture Decision Records

Numbered records of significant, hard-to-reverse decisions, using a light
[MADR](https://adr.github.io/madr/) format (Context / Decision / Alternatives / Consequences as
Positive-Negative-Neutral). ADRs are **immutable once Accepted** — to reverse a decision, add a new
ADR that supersedes the old one, preserving the reasoning history. Every ADR must include rejected
alternatives **and** honest negative consequences: a decision with no trade-offs is an assumption in
disguise. Copy `0000-adr-template.md` for new ones.

| # | Title | Status |
| --- | --- | --- |
| [0001](0001-native-macos-swiftui-spm.md) | Clean Architecture enforced at the SwiftPM target level | Accepted |
| [0002](0002-deployment-target-macos-15.md) | Deployment target macOS 15 | Accepted |
| [0003](0003-ffmpeg-vs-native-audio-strategy.md) | FFmpeg/FFprobe vs native audio APIs (native-first) | Accepted (strategy); native sufficiency = hypothesis pending spike |
| [0004](0004-persistence.md) | Persistence with SwiftData | Proposed (Phase-2 spike) |
| [0005](0005-module-structure.md) | Module structure (seam-driven targets) | Accepted |
| [0006](0006-loudness-truepeak-methodology.md) | Loudness & true-peak methodology | Accepted (approach); constants pending impl |
| [0007](0007-license-and-distribution.md) | License (MIT) and distribution | Accepted |
| [0008](0008-property-availability-and-certainty-model.md) | Explicit property availability & certainty model | Accepted |
| [0009](0009-domain-report-vs-json-contract.md) | Separate domain report from JSON export contract | Accepted |
| [0010](0010-sandboxed-file-access-for-inspection.md) | Sandboxed, temporary file access (no bookmark persistence yet) | Accepted; its entitlement rejection superseded by ADR-0013 |
| [0011](0011-avfoundation-infrastructure-boundary.md) | AVFoundation infrastructure boundary for property reading | Accepted |
| [0012](0012-audio-property-extraction-strategy.md) | Audio property extraction strategy (API priority, reliability tiers) | Proposed (pending ADR-0003 spike) |
| [0013](0013-user-selected-file-access.md) | Read-write access to user-selected files (inspection + export) | Accepted |
| [0014](0014-drag-and-drop-file-access.md) | Drag & drop as a second explicit user-selection mechanism | Accepted |
| [0015](0015-native-pcm-sample-reading.md) | Native PCM sample reading (`AVAudioFile`, bounded by `frameLength`) | Proposed (pending the MP3 case and manual validation) |
