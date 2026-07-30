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
