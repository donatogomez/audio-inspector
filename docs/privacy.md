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

Only **analysis results and file references** — never your audio and never copies of your files:

- file path and a **security-scoped bookmark**,
- content hash, size, modification date,
- computed metrics, warnings, reports, and comparisons,
- the analysis engine version used.

This local database exists so results persist between launches and can be re-shown without
re-analyzing. It can be cleared at any time.

## File access

Files and folders are reached only through macOS's secure mechanisms (the file importer and
security-scoped bookmarks). The app is designed to run under the macOS App Sandbox. Paths and
filenames are treated as untrusted data and never interpolated into shell commands.

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
