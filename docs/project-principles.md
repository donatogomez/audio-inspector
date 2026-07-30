# Project Principles

The guiding principles behind Audio Inspector. They are the tie-breakers when a decision is
unclear; the detailed docs and ADRs elaborate on each.

1. **Evidence before inference before conclusion.** Every statement is labelled as a measured fact,
   a reasoned inference, or a judgment — and judgments always carry a confidence level. See
   [analysis-methodology.md](analysis-methodology.md).

2. **No arbitrary score.** We never reduce a file to "quality: 83/100". We report facts,
   indicators, and explained observations instead.

3. **Format is not quality.** A container/codec (FLAC, WAV) says nothing about the master, source,
   or capture — and higher sample rate/bitrate/bit depth is not automatically better. See
   [vision.md](vision.md).

4. **Honest about uncertainty.** "Inconclusive" is a valid, first-class outcome. We do not assert
   what the signal cannot support, and we surface alternative explanations.

5. **Pure domain, dependencies point inward.** `AudioInspectorDomain` depends on nothing
   framework-side; infrastructure (media, DSP, persistence, UI) depends on the domain, never the
   reverse. See [architecture.md](architecture.md).

6. **Boundaries are enforced, not just documented.** The dependency rule lives in the SwiftPM build
   graph and is backstopped by [`../Scripts/check-boundaries.sh`](../Scripts/check-boundaries.sh).

7. **Reproducible and versioned results.** Given the same input and analysis engine version, output
   is deterministic; thresholds are named constants tied to that version, and test signals are
   seeded. See [testing-strategy.md](testing-strategy.md).

8. **Local, non-destructive, private by construction.** All processing is on-device; original files
   are never modified; no uploads, no telemetry. See [privacy.md](privacy.md).

9. **Spec-driven: OpenSpec is the source of truth.** No significant implementation lands without an
   approved OpenSpec change; specs describe *what*, code follows. See [README.md](README.md).

10. **Important decisions become ADRs.** Hard-to-reverse choices are recorded with their trade-offs
    and rejected alternatives — a decision with no trade-offs is an assumption in disguise. See
    [adr/](adr/README.md).

11. **Truly native macOS.** A professional desktop utility (split view, table, inspector, menus,
    keyboard, accessibility), not a scaled-up iPhone UI.

12. **Small, reviewable changes; grow only at real seams.** Prefer minimal increments and add
    modules/abstractions only when a genuine boundary appears — never speculatively.
