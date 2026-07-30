# ADR-0002: Deployment target macOS 15

- **Status**: Accepted
- **Date**: 2026-07-30
- **Deciders**: Project maintainer
- **Related**: ADR-0001, ADR-0004

## Context

We must pick a minimum macOS version. The development machine runs macOS 26 with Xcode 26 / Swift
6.3, so newer APIs are available, but the deployment target defines the installable user base. The
brief says "macOS 15 or higher, unless there is a well-documented technical reason to choose
another minimum."

## Decision

Target **macOS 15** as the minimum deployment version.

## Alternatives considered

- **macOS 26 minimum.** Access to the very latest APIs, but drastically shrinks the addressable
  audience for a collector/audiophile tool where users are not always on the newest OS. No MVP
  feature requires macOS 26. Rejected (revisit only if a concrete, high-value API demands it).
- **macOS 14 or earlier minimum.** Widens reach slightly but forgoes maturity in SwiftUI (Table,
  inspector ergonomics) and SwiftData that we rely on, and increases the API-availability tax.
  Rejected.

## Consequences

### Positive
- Broad installable base; mature SwiftUI + SwiftData; simpler availability handling.

### Negative / costs
- Cannot unconditionally use macOS 26-only APIs (guard with `if #available` when needed).

## Follow-ups

The CI runner + Xcode combination must support building for macOS 15 and will be verified against
currently-available GitHub Actions images before CI is added (do not assume a runner exists —
verify).
