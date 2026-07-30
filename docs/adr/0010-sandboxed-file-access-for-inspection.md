# ADR-0010: Sandboxed, temporary file access for inspection (no bookmark persistence yet)

- **Status**: Accepted
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: SECURITY.md, docs/privacy.md, ADR-0004 (persistence, deferred), change add-basic-audio-file-inspection

## Context

Audio Inspector runs under the macOS App Sandbox (ADR-0002 target, `App/.../*.entitlements` = App
Sandbox only). The first slice must let the user pick a local file and read it, without introducing
persistence (deferred to Phase 2, ADR-0004) and without weakening the sandbox. Absolute user paths
are sensitive (`docs/privacy.md`) and are not a stable identity.

## Decision

- **Selection**: the native open panel (SwiftUI `fileImporter` / `NSOpenPanel`). Choosing a file
  grants the app user-scoped read access to exactly that file — **no broad entitlement** beyond App
  Sandbox is added.
- **Access lifetime**: access is held only for the **duration of a single inspection** via
  `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` (balanced in a
  `defer`). Nothing is retained afterward.
- **No bookmark persistence** in this slice: security-scoped bookmarks (for re-access across launches)
  belong with persistence (ADR-0004, Phase 2) and are explicitly out of scope here.
- **Identity & output**: the absolute path is **not** treated as stable identity and is **not**
  exported by default. The result carries a sandbox-safe representation (display name + last path
  component); redaction happens in the export mapping layer (ADR-0009).

## Alternatives considered

- **Persist a security-scoped bookmark now.** Would enable recent-files/re-access, but pulls
  persistence into this slice (out of scope) and stores a path-derived identity prematurely.
  Rejected; deferred to Phase 2.
- **Add `com.apple.security.files.user-selected.read-write` or broader entitlements.** Not needed —
  inspection is read-only and single-file. Rejected (minimum-necessary entitlements).
- **Export the absolute path for traceability.** Leaks private paths by default; violates
  `docs/privacy.md`. Rejected; use the safe representation.

## Consequences

### Positive
- Minimal sandbox surface; no persistence coupling; privacy-preserving output; access is scoped and
  released deterministically.

### Negative / costs
- No cross-launch re-access yet (must re-pick the file) — acceptable for the MVP slice.

### Neutral
- Sets the pattern that persistence + bookmarks arrive together in Phase 2, not piecemeal.

## Follow-ups

Bookmark persistence and stable file identity are designed with the persistence work (ADR-0004,
Phase 2). Safe-path representation format is finalized in the slice (see change design Open
Questions).
