# Security Policy

Audio Inspector processes audio **entirely on the user's machine**. There is no backend, no
account system, and no data transmission. The threat model is therefore local and input-driven.

## Design principles

- **No network for analysis.** The app performs no uploads and no telemetry. Any future network
  feature (e.g. optional update checks) will be explicit and opt-in.
- **Read-only on user data.** Original files are never modified — the only file the app writes is the
  JSON export destination the user picks. Tag writing, if added, will require explicit per-action
  confirmation.
- **Untrusted input.** Audio files, filenames, paths, and embedded metadata are treated as
  hostile input. Malformed or malicious files must never cause code execution, path escape, or
  unbounded resource use.
- **Safe external processes.** When FFmpeg/FFprobe (or any subprocess) is used, arguments are
  always passed as a separated argument vector via `Process` — never as an interpolated shell
  string. No `sh -c`. See [docs/adr/0003-ffmpeg-vs-native-audio-strategy.md](docs/adr/0003-ffmpeg-vs-native-audio-strategy.md).
- **Sandboxed, user-granted file access.** The app runs under the macOS App Sandbox and reaches files
  only through explicit user interactions — a native panel or dragging the file onto the window — so
  access is granted per item by the user; no folder-wide or system-wide entitlement. Because one
  executable setting covers every user-selected item, the app declares
  `com.apple.security.files.user-selected.read-write`, which the JSON export requires; the inspected
  audio file is still treated as strictly read-only by design. Access is held only for the operation
  that needs it, and **no URL or security-scoped bookmark is persisted** in this phase — future
  bookmark support is a separate decision and scope. See
  [ADR-0010](docs/adr/0010-sandboxed-file-access-for-inspection.md),
  [ADR-0013](docs/adr/0013-user-selected-file-access.md) and
  [ADR-0014](docs/adr/0014-drag-and-drop-file-access.md).
- **Bounded resources.** Streaming, chunked reads, capped concurrency, and cooperative
  cancellation prevent a crafted file from exhausting memory or CPU.
- **Logs without sensitive data.** Structured `OSLog` output must not leak file contents or full
  personal paths beyond what is necessary for diagnostics.

## Reporting a vulnerability

The project is in early bootstrap and not yet distributed. Once releases exist, this section will
describe a private disclosure channel. Until then, report concerns via a **private** GitHub
Security Advisory on this repository rather than a public issue.

## Scope

In scope: memory-safety and resource-exhaustion issues from crafted audio input; command/argument
injection via filenames or metadata; sandbox-escape or unintended file access; accidental network
egress.

Out of scope (for now): distribution/notarization signing (tracked as a future decision), and any
server-side concern (there is no server).
