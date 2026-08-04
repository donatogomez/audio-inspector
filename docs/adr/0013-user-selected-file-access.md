# ADR-0013: Permit read-write access to user-selected files (inspection + export)

- **Status**: Accepted
- **Date**: 2026-08-04
- **Deciders**: Project maintainer
- **Related**: ADR-0010 (supersedes only its entitlement rejection), ADR-0002, ADR-0009, SECURITY.md,
  docs/privacy.md, change add-basic-audio-file-inspection (groups 5–7)

## Context

Audio Inspector runs under the macOS App Sandbox (ADR-0002; `App/AudioInspector/*.entitlements`).
Two user-driven file operations now exist in the accepted slice:

- it **inspects** an audio file the user chooses with `NSOpenPanel` (group 6);
- it **exports** a `schemaVersion` 1 JSON report to a destination the user chooses with `NSSavePanel`
  (group 5, already integrated).

App Sandbox grants access to those items dynamically, through the powerbox, gated by the
**User Selected File** entitlement:

- `com.apple.security.files.user-selected.read-only` lets the app **read** the audio file the user
  picked, but does **not** let it write the JSON anywhere outside its own container — the save panel
  would present a destination the app then cannot write to;
- `com.apple.security.files.user-selected.read-write` is what the save flow requires.

Critically, **the entitlement is a property of the executable, not of an individual panel**: an app
cannot declare read-only for its open panel and read-write for its save panel independently. One
setting covers every user-selected item. So supporting both operations forces the read-write value.

ADR-0010 rejected `…user-selected.read-write` on the grounds that "inspection is read-only and
single-file". That reasoning was correct for inspection alone, but it predates the export-to-a-chosen
destination capability, which cannot work under read-only. Left unaddressed, the shipped `.app` would
present a save panel and then fail to write — a defect invisible to `swift test`, which runs
unsandboxed through SwiftPM.

## Decision

- **Enable `com.apple.security.files.user-selected.read-write`** in the app target's entitlements,
  and **do not** additionally declare `…user-selected.read-only` (the read-write value already covers
  reading; declaring both is redundant).
- **Scope stays "what the user explicitly picked"** — access is extended only to items chosen through
  a panel. No folder, home-directory, or full-disk entitlement is added.
- **The source audio file is treated as strictly read-only by design and by code.** No own API
  exposes an operation that writes to, moves, renames, or deletes the inspected file; the reading
  adapter only opens it for reading.
- **The only thing Audio Inspector writes is the export destination** returned by `NSSavePanel`.
- **No URL is persisted and no security-scoped bookmark is created** — each access is a one-shot
  operation.
- **Security-scoped access is held only for the operation that needs it**, balanced with `defer`
  (unchanged from ADR-0010).
- **Group 7 verifies by hash that the original file is byte-identical before and after** an
  inspection, turning the read-only promise into an executable check.

## Alternatives considered

- **Keep `…user-selected.read-only` only.** Preserves the strongest entitlement-level guarantee, but
  breaks the accepted `NSSavePanel` export: the app could not write the JSON to the destination the
  user picked. Rejected.
- **Add a broad folder entitlement** (e.g. Downloads, Documents, or full disk). Would allow writing
  without a panel, but grants far more access than the product needs and removes the per-item user
  consent that makes the sandbox meaningful. Rejected as excessive.
- **Persist security-scoped bookmarks** to re-acquire access later. Unnecessary for one-shot
  operations and pulls persistence into the MVP (ADR-0004, Phase 2). Rejected; ADR-0010's deferral
  stands.
- **Write the JSON only inside the app container** (then let the user move it). Cheap and needs no
  entitlement change, but contradicts the accepted requirement that the user chooses the export
  destination. Rejected.
- **Drop the export feature.** Would remove the need for write access entirely, but contradicts the
  accepted scope (AC.4) and the shipped group-5 work. Rejected.

## Consequences

### Positive

- Real selection and inspection work under App Sandbox, and the export writes successfully outside
  the container.
- No broad folder or system-wide entitlement is introduced; **the user still grants every single
  access**, item by item, through a native panel.
- The two panel-driven flows share one coherent, minimal permission model.

### Negative / costs

- The sandbox extension issued for a user-selected item now **technically permits writing to it** —
  including, in principle, the audio file the user opened for inspection.
- **The read-only protection of the source file is no longer enforced by the entitlement.** It is now
  a property of our own design rather than of the platform.
- That protection must therefore be upheld by other means: architecture boundaries (only
  `AudioInspectorMedia` opens the audio, and only for reading; only the export coordinator writes,
  and only to the save-panel URL), APIs that expose no write capability over the source, and the
  end-to-end hash check in group 7. This is a real weakening of a platform guarantee, accepted
  knowingly.

### Neutral

- The entitlement value is a single line in the app target; no code in the package depends on it.
- Should bookmarks arrive with persistence (ADR-0004, Phase 2), this decision does not change: the
  scope stays "items the user explicitly selected".

## Relationship to ADR-0010

ADR-0010 **remains in force** for everything else it decided: native-panel selection, access held only
for the duration of a single inspection via `startAccessingSecurityScopedResource()` /
`stopAccessingSecurityScopedResource()` balanced in a `defer`, **no bookmark persistence** in this
slice, and the absolute path never treated as identity nor exported (the safe `source` object stands).

This ADR supersedes **only** ADR-0010's rejection of
`com.apple.security.files.user-selected.read-write` in its "Alternatives considered" section. ADR-0010
is not rewritten: per `docs/adr/README.md`, accepted ADRs are immutable and are changed only by a
superseding record such as this one.

## Follow-ups

The entitlement value itself is changed with the implementation of task 6.1 (the open-panel selection
work), not by this record — the decision is documented before the capability changes. Task 7.2 must
assert the source file's hash is unchanged across an inspection, which is what now backs the
read-only promise.
