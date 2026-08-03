# CLAUDE.md — Audio Inspector

The session router for AI-assisted work. Global preferences (Spanish communication, Conventional
Commits without AI co-author trailers, native-platform bias, Swift/SwiftUI/Swift-Concurrency) still
apply. This file stays short: it routes to the sources of truth and states only the binding rules and
the resume protocol. It does **not** re-explain the project — that is `OVERVIEW.md`.

## Start every session here

1. Read **`OVERVIEW.md`** — the invariants, architecture, domain model, and where everything lives. It
   is binding.
2. Read **`CURRENT.md`** — the last working focus and next step (it may be empty; that is normal).
3. Derive the **real state from tools, never from prose**:
   - `OPENSPEC_TELEMETRY=0 openspec list` and the active change's `tasks.md` → task status.
   - `git status` · `git branch` · `git log --oneline -10` → code and branch state.

## Keeping `CURRENT.md`

- Update it when you **pause, finish a thread, or change focus.** Overwrite the snapshot; never append a
  log.
- Write only: current **focus**, the **next step**, **why**, and **open questions**.
- Never write there: task lists (OpenSpec), branch/commit facts as truth (git), decisions (ADRs),
  explanations (docs / OVERVIEW), or rules (here). It is never a source of truth and may be left empty.

## Binding rules (canonical statements live in `OVERVIEW.md` / the ADRs — obey them)

Named here so they are in context every session; when detail is needed, `OVERVIEW.md` and the ADRs are
authoritative:

- **Spec-driven** — no significant implementation without an approved OpenSpec change.
- **Architecture boundaries** (full rules in `OVERVIEW.md` §2) — the dependency rule is build-enforced;
  **Media is the only home of AVFoundation/AudioToolbox/`Process`**, and **no framework type or error
  crosses a domain port.** Run `./Scripts/check-boundaries.sh` before pushing.
- **Concurrency** — Swift 6 strict; `actor` for shared mutable state, `Sendable` values otherwise; no
  `@unchecked Sendable`, no `DispatchQueue`/locks.
- **Analysis honesty** — separate evidence/inference/conclusion; confidence levels; no aggregate score;
  never invent a value; never assert transcoding from a single frequency cutoff.
- **Safety** — never modify originals; everything local; disclose no path/URL/bookmark by default; pass
  separated argument vectors to `Process`, never `sh -c`.

## Git & finishing

- Work on a branch, **never on `main`. Do not commit or push without explicit user approval.** Small,
  single-purpose PRs (`.github/pull_request_template.md`).
- **Definition of done** = four green gates — architecture boundaries, a zero-warnings build, the test
  suite, and OpenSpec strict validation. Exact commands + environment live in `CONTRIBUTING.md`.

## Where detail lives (do not restate it here)

Orientation → `OVERVIEW.md` · decisions → `docs/adr/` · architecture → `docs/architecture.md` ·
concurrency → `docs/concurrency.md` · testing → `docs/testing-strategy.md` · JSON contract →
`docs/json-schema-v1.md` · workflow & commands → `CONTRIBUTING.md`.
