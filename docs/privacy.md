# Privacy

Audio Inspector is built to be private by construction, not by policy alone.

## What the app does

- **All analysis runs locally** on your Mac. Audio is decoded and analyzed on-device.
- **No uploads.** Your audio never leaves your machine.
- **No telemetry, no analytics.** The app collects no usage data and phones home to no one by
  default. Any future network feature (e.g. an update check) will be explicit and opt-in.
- **Originals are never modified.** Analysis is strictly read-only. If tag writing is ever added,
  it will require explicit, per-action confirmation and will be clearly separated from analysis.

## What the app stores locally

**Today: nothing.** The app keeps no database, remembers no file between launches, and stores no
bookmark. Close it and it forgets everything; inspecting a file again means picking it again.

When result persistence arrives (a later phase), it will store **analysis results and file
references** — never your audio and never copies of your files:

- file path and a **security-scoped bookmark**,
- content hash, size, modification date,
- computed metrics, warnings, reports, and comparisons,
- the analysis engine version used.

That local database will exist so results persist between launches and can be re-shown without
re-analyzing, and it will be clearable at any time.

## File access

Files are reached only through macOS's secure mechanisms: you choose each one explicitly — in a native
open or save panel, or by dragging it onto the window — and the app holds that access only for the
operation that needs it. It runs under the macOS App Sandbox. Paths and filenames are treated as
untrusted data and never interpolated into shell commands. Security-scoped bookmarks — the mechanism
that would let the app re-open a file across launches — are **not** used yet; they arrive with result
persistence.

**What the sandbox allows vs. what the app does.** The app requests access only to items *you*
explicitly choose, in a panel or by dropping them (ADR-0014) — no folder-wide or system-wide
entitlement. Because one setting covers
every user-selected item, that access is read-write (ADR-0013). What the app actually does with it is
narrower: **the audio file you inspect is only ever read** — no code path writes to, renames, moves,
or deletes it — and **the single file the app writes is the export destination you choose** in the
save panel. Nothing is written back to your library.

## Logs

Diagnostic logging uses `OSLog` and avoids recording file contents or unnecessary personal path
information.

## Developer tooling telemetry (not the app)

The **OpenSpec** developer CLI used to build this project collects anonymous usage statistics by
default. This is a build-time tool, unrelated to the shipped app, but this project opts out on
principle:

```bash
export OPENSPEC_TELEMETRY=0   # or DO_NOT_TRACK=1
```

CI sets `OPENSPEC_TELEMETRY=0`. Contributors are encouraged to export it in their shell profile
(the project setup added it to the maintainer's `~/.zshrc`).
