#!/usr/bin/env bash
#
# check-boundaries.sh — enforce Audio Inspector's Clean Architecture import rules.
#
# Why this exists: SwiftPM scopes each target's *declared* dependencies, so on a clean/isolated
# build an undeclared `import` fails with "no such module". But on a full `swift build` SwiftPM
# emits every module into one shared search directory, so an accidental undeclared import can slip
# through locally. This script closes that gap (locally and in CI) by statically rejecting forbidden
# imports. Adapted from the SignalFlow reference (docs/signal-flow-reuse-audit.md) to Audio
# Inspector's smaller module set. See docs/architecture.md.
#
# Exit non-zero on the first violation.

set -euo pipefail
cd "$(dirname "$0")/.."

# Pre-code state: nothing to check until the package exists. Don't fail the build for that.
if [ ! -d Sources ]; then
    echo "ℹ️  Sources/ not present yet — no boundaries to check (bootstrap phase)."
    exit 0
fi

fail=0
report() { echo "❌ boundary violation: $1"; fail=1; }

# Frameworks that the pure Domain (and pure DSP) must never see.
UI_FRAMEWORKS='SwiftUI|AppKit'
MEDIA_FRAMEWORKS='AVFoundation|AudioToolbox|CoreAudio|AVFAudio'

# Rule 1 — AudioInspectorDomain is pure: no first-party module, no UI, no media/DSP frameworks,
# no persistence. (Foundation value types are allowed; frameworks are not.)
if [ -d Sources/AudioInspectorDomain ] && \
   grep -REn "^\s*import\s+(AudioInspectorAnalysis|AudioInspectorMedia|AudioInspectorTesting|Feature[A-Za-z]+|AudioInspectorApp|DesignSystem[A-Za-z]*|${UI_FRAMEWORKS}|${MEDIA_FRAMEWORKS}|Accelerate|SwiftData)\b" \
        Sources/AudioInspectorDomain 2>/dev/null; then
    report "AudioInspectorDomain must import nothing but the standard library / Foundation value types"
fi

# Rule 2 — Domain and Analysis must not spawn subprocesses (no Process / shell). Only Media may.
if grep -REn '\bProcess\s*\(' Sources/AudioInspectorDomain Sources/AudioInspectorAnalysis 2>/dev/null; then
    report "Domain/Analysis must not use Process(...) — subprocess use belongs in AudioInspectorMedia"
fi

# Rule 3 — AudioInspectorAnalysis is pure DSP: DomainKit + Accelerate only. No UI, no media I/O
# frameworks, no Media/Feature/App modules.
if [ -d Sources/AudioInspectorAnalysis ] && \
   grep -REn "^\s*import\s+(AudioInspectorMedia|Feature[A-Za-z]+|AudioInspectorApp|DesignSystem[A-Za-z]*|${UI_FRAMEWORKS}|${MEDIA_FRAMEWORKS}|SwiftData)\b" \
        Sources/AudioInspectorAnalysis 2>/dev/null; then
    report "AudioInspectorAnalysis may depend only on AudioInspectorDomain (+ Accelerate)"
fi

# Rule 4 — AudioInspectorMedia is the infrastructure adapter (AVFoundation/AudioToolbox/FFmpeg via
# Process). It must not reach up into UI, features, or the app.
if [ -d Sources/AudioInspectorMedia ] && \
   grep -REn "^\s*import\s+(Feature[A-Za-z]+|AudioInspectorApp|DesignSystem[A-Za-z]*|${UI_FRAMEWORKS}|SwiftData)\b" \
        Sources/AudioInspectorMedia 2>/dev/null; then
    report "AudioInspectorMedia must not import UI, feature, app, or persistence modules"
fi

# Rule 5 — Feature modules are vertical UI slices: DomainKit (+ a future DesignSystem) only. They
# must never reach the infrastructure/analysis concretes or media/DSP frameworks.
for feature in Sources/Feature*; do
    [ -d "$feature" ] || continue
    if grep -REn "^\s*import\s+(AudioInspectorMedia|AudioInspectorAnalysis|${MEDIA_FRAMEWORKS}|Accelerate|SwiftData)\b" "$feature" 2>/dev/null; then
        report "$(basename "$feature") must not import a concrete infrastructure/analysis module or a media/DSP framework"
    fi
done

# Rule 6 — Media frameworks are owned exclusively by AudioInspectorMedia. No other module (not even
# the app composition root, which depends on the Media *target*) may import them directly.
media_violators=$(grep -REln "^\s*import\s+(${MEDIA_FRAMEWORKS})\b" Sources 2>/dev/null | grep -v '^Sources/AudioInspectorMedia/' || true)
if [ -n "$media_violators" ]; then
    report "AVFoundation/AudioToolbox may only be imported by AudioInspectorMedia (found: $media_violators)"
fi

# Rule 7 — Accelerate is owned by AudioInspectorAnalysis (pure DSP). No other module imports it.
accel_violators=$(grep -REln '^\s*import\s+Accelerate\b' Sources 2>/dev/null | grep -v '^Sources/AudioInspectorAnalysis/' || true)
if [ -n "$accel_violators" ]; then
    report "Accelerate may only be imported by AudioInspectorAnalysis (found: $accel_violators)"
fi

# Rule 8 — AudioInspectorTesting is a test-only support module (fixtures, port fakes, builders).
# No production target may depend on it — only test targets (which live under Tests/, not Sources/).
# So no file under Sources/ may import it.
testing_violators=$(grep -REln '^\s*import\s+AudioInspectorTesting\b' Sources 2>/dev/null | grep -v '^Sources/AudioInspectorTesting/' || true)
if [ -n "$testing_violators" ]; then
    report "AudioInspectorTesting is test-only — no Sources/ target may import it (found: $testing_violators)"
fi

# Rule 9 — the product is offline by construction (docs/privacy.md, SECURITY.md). No production
# source may reach the network. This is the *structural* half of the guarantee; the configuration
# half (no network entitlement, which is what the sandbox actually enforces) is asserted by
# Tests/AudioInspectorKitTests/OfflineConfigurationTests.swift, and observing real traffic belongs to
# docs/manual-validation-mvp.md. Neither this rule nor those tests claim to prove that no traffic
# occurs — they prove the code has no way to ask for it and the sandbox would refuse it.
#
# Matching is deliberately narrow to avoid firing on prose: imports are anchored to an `import` line,
# and the type names must appear as a whole word followed by `(` or `.` — i.e. actually used, not
# merely mentioned in a comment such as "no URLSession here".
NETWORK_MODULES='Network|WebKit|CFNetwork|NetworkExtension'
NETWORK_TYPES='URLSession|URLRequest|NWConnection|NWListener|NWBrowser|WKWebView|CFSocket|NSURLConnection'
if [ -d Sources ]; then
    if grep -REn "^\s*import\s+(${NETWORK_MODULES})\b" Sources 2>/dev/null; then
        report "production code must not import a networking framework (the app is offline by construction)"
    fi
    if grep -REn "\b(${NETWORK_TYPES})\s*[(.]" Sources 2>/dev/null | grep -vE '^\s*[^:]+:[0-9]+:\s*(///|//|\*)'; then
        report "production code must not use a networking API (the app is offline by construction)"
    fi
fi

# Rule 10 — Feature modules are location-free (ADR-0010, ADR-0014). A UI slice must never handle a
# filesystem location or platform UI: URLs, panels and the sandbox belong to AudioInspectorApp, which
# hands features an opaque action instead. The compiler cannot catch this — `URL` comes from
# Foundation, which features legitimately use for other value types — so it is enforced statically
# here. Foundation itself stays allowed; only the `URL` type and AppKit are rejected.
#
# Matching, like Rule 9, is deliberately narrow: `.swift` files only, `URL` as a whole word (so
# `fileURL`, `URLSession` and the plural `URLs` in prose do not trip it), and comment lines — `//`,
# `///` and `*` continuation lines inside block comments — filtered out, because the feature sources
# legitimately explain that they never handle a `URL`.
for feature in Sources/Feature*; do
    [ -d "$feature" ] || continue
    name=$(basename "$feature")

    if grep -REn --include='*.swift' "^\s*import\s+AppKit\b" "$feature" 2>/dev/null; then
        report "$name must not import AppKit — panels and platform UI live in AudioInspectorApp"
    fi

    if grep -REn --include='*.swift' '\bURL\b' "$feature" 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(///|//|\*)'; then
        report "$name must not use the URL type — features are location-free (ADR-0010, ADR-0014)"
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "✅ architecture boundaries respected"
fi
exit "$fail"
