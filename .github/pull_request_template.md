<!--
Audio Inspector PR template (adapted from SignalFlow — see docs/signal-flow-reuse-audit.md).
Keep PRs small and single-purpose. `main` must stay green. Implementation follows an approved
OpenSpec change — link it below.
-->

## Summary
<!-- What does this PR do, in one or two sentences? -->

## Why
<!-- The rationale. What problem does it solve / what value does it add? -->

## Changes
<!-- Bullet the notable changes. Keep the diff focused — no unrelated drive-bys. -->
-

## Spec alignment
- [ ] Implements work from an approved OpenSpec change (linked below); nothing outside its scope
- [ ] Affected scenarios are covered by tests
- [ ] `openspec validate <change> --strict` passes

OpenSpec change: <!-- e.g. openspec/changes/<name>, or "docs-only / n/a" -->

## Architecture
- [ ] No new cross-boundary imports (`AudioInspectorDomain` stays pure; features don't import Media/Analysis; AVFoundation/AudioToolbox stay in Media)
- [ ] Relevant ADR referenced below, or a new ADR added if a significant decision was made

Related ADR(s): <!-- e.g. ADR-0003, or "n/a" -->

## Testing
<!-- What did you verify, and how? Paste relevant command output. -->
- [ ] `swift build`
- [ ] `swift test` (tests added/updated for new behavior)
- [ ] `./Scripts/check-boundaries.sh`

## Forensic-honesty check (analysis PRs)
- [ ] No aggregate 0–100 "quality score" introduced
- [ ] New observations carry a confidence level and, where relevant, alternative explanations
- [ ] Units/scales (dBFS, LUFS, linear vs log) are explicit; thresholds tied to the engine version

## Trade-offs / follow-ups
<!-- Honest notes on limitations, deferred work, or things a reviewer should know. -->

## Self-review checklist
- [ ] Single-purpose and reviewable in one sitting
- [ ] Conventional Commit title (squash-merge subject); no AI co-author trailer
- [ ] `main` will remain stable after merge
- [ ] Original audio files are never modified; no network access added
