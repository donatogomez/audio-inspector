# ADR-0003: FFmpeg/FFprobe vs native audio APIs — a native-first, FFmpeg-abstracted strategy

- **Status**: Accepted (strategy & MVP packaging: FFmpeg **not** bundled). Native-API *sufficiency*
  is an **open hypothesis pending a spike** (see below).
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: ADR-0007 (license), SECURITY.md, docs/analysis-methodology.md, docs/roadmap.md

## Context

We need to probe containers and decode MP3, WAV, AIFF, FLAC, ALAC, AAC, and M4A, and to compute
loudness/true-peak and other diagnostics. Two families are available:

- **Native Apple APIs** — AVFoundation, `ExtAudioFile`/AudioToolbox, Accelerate/vDSP. These are
  *expected* to decode the seven target formats on macOS 15 (FLAC and ALAC included) with no
  third-party dependency, no extra binary to ship, first-class sandbox/signing behavior, and Apple
  Silicon + Intel support. **This sufficiency is a hypothesis, not yet verified** (see "Open
  hypotheses" below) — we do not assert it as fact.
- **FFmpeg / FFprobe** — excellent, broad format/diagnostic coverage and battle-tested loudness
  filters (`ebur128`, `loudnorm`, `astats`, `silencedetect`, error/stream reporting). But it is a
  large external component with real **licensing and distribution** consequences.

The FFmpeg installed on the dev machine is the **Homebrew GPL build** (`--enable-gpl
--enable-version3`). Key distribution facts:

- **Licensing.** A default/GPL FFmpeg build makes any binary that ships it GPL — incompatible with
  a permissive app license and problematic for the Mac App Store. An **LGPL** build (no
  `--enable-gpl`/`--enable-nonfree`, dynamically linked) is far friendlier but requires building
  our own FFmpeg and honoring LGPL relinking obligations. This is coupled to ADR-0007.
- **Packaging.** Options are: (a) invoke a system/bundled **CLI binary** via `Process`;
  (b) **link libav\*** libraries; (c) don't ship FFmpeg at all. A bundled executable or dylibs
  must be **signed with our Team ID, use the hardened runtime, and be notarized**; the sandboxed
  child inherits our sandbox and needs bookmarked file access. Bundling adds tens of MB and a
  universal (arm64 + x86_64) build burden.
- **Sandbox.** Shipping and spawning an embedded executable under App Sandbox + hardened runtime is
  possible but adds signing/entitlement complexity; native APIs avoid it entirely.

## Decision

Adopt a **native-first** strategy, with FFmpeg strictly behind Domain protocols:

1. **All audio I/O sits behind Domain protocols** (`AudioProbing`, `AudioDecoding`, and the
   loudness/analysis protocols). The domain never knows whether native code or FFmpeg produced a
   result.
2. **Native APIs are the intended shipping path** for decoding and DSP — *pending validation of the
   sufficiency hypotheses below*. If a spike shows a native gap for a specific format or property,
   the abstraction lets FFmpeg cover it in dev/test while we decide (it does not force a shipping
   dependency).
3. **FFmpeg/FFprobe are an optional, abstracted adapter** used during **development and CI** (and
   as a reference oracle — `ebur128` values, quick container probing — while we validate native
   loudness). It is a **dev/test dependency**, not a shipping requirement.
4. **The shipped MVP does not bundle or distribute any FFmpeg component** (firm decision). Revisiting
   this would require a concrete native gap *and* a new/updated ADR; the choice would then be an
   **LGPL dynamic-link build** (never GPL, per ADR-0007) or dropping the feature.
5. **All subprocess calls are safe by construction**: separated argument vectors via `Process`
   (never `sh -c`, never string interpolation of paths), explicit **audio-stream selection** on
   every FFmpeg/FFprobe call so cover art and non-audio streams never contaminate metrics.

## Open hypotheses (pending a native-decoding spike)

Native-first is the direction, but its **technical sufficiency is unproven**. Before committing MVP
decoding to native APIs, a spike must validate — against **real and synthetic fixtures** for all of
MP3, WAV, AIFF, FLAC, ALAC, AAC, M4A — each of:

- **Read/decode compatibility**: every target format actually decodes correctly via AVFoundation/
  `ExtAudioFile`.
- **Reliable properties**: bit depth, sample rate, channel layout, and duration are exposed
  accurately (not just the container's declared values).
- **Damaged-file behavior**: truncated/corrupt files fail gracefully (recoverable errors, no crash,
  bounded resource use) rather than silently producing garbage.
- **Deep stream validation**: whether native decode surfaces frame-level errors comparably to
  FFmpeg, or whether FFprobe/FFmpeg is needed for integrity checks (Phase 2).
- **Metadata & extra streams**: tags and non-audio streams (cover art) are read without contaminating
  audio metrics, with explicit audio-stream selection.
- **Differences vs FFprobe**: where native property/inspection results diverge from FFprobe, and
  which is authoritative.
- **Large-file performance**: streamed decode stays bounded in memory and acceptable in time on
  large files.

Until the spike passes, no claim of "native APIs are sufficient" is asserted as fact. The spike is
an early Phase-1 task (see the bootstrap change's tasks).

## Alternatives considered

- **FFmpeg-only (CLI or libav) as the engine.** Fastest to broad coverage, but couples the product
  to GPL/packaging/notarization/size problems and a heavy sandbox story. Rejected as the primary
  path; kept as an abstracted, optional adapter.
- **Native-only, no FFmpeg anywhere.** Cleanest shipping story, but FFmpeg is genuinely useful for
  reference loudness values and quick container diagnostics during development. Rejected as too
  strict for the dev phase; embraced as the target for the *shipped* binary.

## Consequences

### Positive
- No licensing/notarization/size tax on the default build; clean sandbox story; native performance;
  FFmpeg available as a reference oracle to validate our DSP.

### Negative / costs
- We must implement (and test against FFmpeg) our own loudness/true-peak/spectral code rather than
  shelling out; some diagnostics may arrive later than if we leaned on FFmpeg.

### Neutral
- The `AudioInspectorMedia` target becomes the sole, clearly-bounded home of any FFmpeg code.

## Follow-ups

Run the native-decoding spike early in Phase 1 and record its results (updating this ADR if a gap is
found); pin loudness/true-peak methodology (ADR-0006); enforce Media-only FFmpeg/`Process` use via
`Scripts/check-boundaries.sh`. The MVP ships without FFmpeg regardless.
