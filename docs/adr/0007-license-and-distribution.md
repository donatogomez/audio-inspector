# ADR-0007: License (MIT) and distribution

- **Status**: Accepted
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: ADR-0003 (FFmpeg strategy)

## Context

The project needs a license, and the choice is **coupled to the FFmpeg decision (ADR-0003)**: a
shipped build that bundles GPL FFmpeg must be GPL-compatible, whereas a native-only (or LGPL
dynamically-linked) build keeps permissive licensing viable. ADR-0003 commits to **not bundling
FFmpeg in the MVP** (FFmpeg is a development/test tool only), which keeps permissive options open.

## Decision

License the project under **MIT**. A `LICENSE` file (MIT, © 2026 Donato Gómez) is committed at the
repository root. This is consistent with ADR-0003: because FFmpeg is not distributed inside the app,
MIT imposes no conflict.

## Alternatives considered

- **Apache-2.0** — permissive with an explicit patent grant; heavier boilerplate. Rejected in
  favor of MIT's simplicity for a solo project.
- **GPL-3.0** — would be required only if we bundled GPL FFmpeg; makes the whole app GPL and
  complicates App Store distribution. Rejected because ADR-0003 does not bundle FFmpeg.

## Consequences

### Positive
- Maximum adoption/reuse; minimal legal friction; compatible with the native-first strategy.

### Negative / costs
- If the project ever *must* bundle GPL FFmpeg, MIT would conflict and a new ADR (superseding this
  and revisiting ADR-0003) would be required.

### Neutral
- Distribution specifics (signing, hardened runtime, notarization, universal binary) remain a
  Phase-8 concern tracked here and in ADR-0003; MIT does not constrain them.

## Follow-ups

Revisit only if a native-API gap forces bundling GPL FFmpeg (see ADR-0003 open hypotheses).
