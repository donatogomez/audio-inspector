# ADR-0017: Semantics of a two-file technical comparison

- **Status**: **Proposed.** It stays Proposed until the comparison exists against production code and
  its surface has been validated with a person looking at it. Partial evidence does not promote it.
- **Date**: 2026-08-07
- **Deciders**: Project maintainer
- **Related**: **ADR-0008** (property availability and certainty — this record applies its discipline
  one level up; *referenced, not edited*), ADR-0009, ADR-0010, ADR-0012,
  `docs/analysis-methodology.md`, `docs/vision.md`, change `add-two-file-technical-comparison`

## Context

The product's own vision names the question directly — *"Which of my three copies of this album is the
best one to keep?"* — and the roadmap places version comparison in Phase 7, with an explicit guard:
*"never auto-picking highest SR/bitrate/bit depth."* The question the user asks and the answer the
product may honestly give are therefore **not the same question**, and the gap between them is where
this instrument would most easily become an oracle.

Four different questions hide inside "compare two files":

1. **Are these the same file?** Byte identity. Objective, trivial, and almost never what is meant.
2. **Are these the same recording?** Needs time alignment, gain matching and correlation. Every step is
   threshold-dependent.
3. **Which observable technical facts are the same, different, or not comparable?** Objective, and
   answerable today from data the app already produces.
4. **Which one is better?** A verdict. Product invariant #1 (honesty over verdicts), #3 (no aggregate
   score) and #4 (format ≠ quality) forbid it in that form.

This record fixes the semantics of **question 3 only**, because the modelling decision it forces is the
one everything else is built on.

That decision is not obvious. **Comparing two files is not comparing two numbers — it is comparing two
`Property<Value>` values.** If one file reports `bitDepth = .available(16)` and the other reports
`bitDepth = .unsupported` because its codec is lossy, the honest answer is **not** "different". Nothing
was compared. Saying "different" manufactures a fact out of an absence, which is exactly what ADR-0008
made unrepresentable one level down. A comparison modelled as a `Bool` inherits none of that protection
and loses it for the whole feature.

## Decision

### 1. A comparison is an observation, never a judgement

A comparison SHALL state whether two observable technical facts are the same, different, or not
comparable. It SHALL NOT state, imply, rank, order or score which file is better, preferable, more
authentic, higher quality or worth keeping. This is not a UI guideline; it is a constraint on the
types, and the types below are chosen so that a verdict has nowhere to live.

### 2. Three-way semantics, exhaustive, mirroring ADR-0008

A per-property comparison is an **exhaustive sum type** over three cases:

- **`same(value)`** — both sides are `available` and their values are equal by the field's own exact
  criterion. The value is carried once, because both sides hold it.
- **`different(first:second:)`** — both sides are `available` and their values are not equal. Both
  values are carried **as the evidence for that statement**.
- **`incomparable(gap)`** — anything else. A first-class outcome, not an error and not a gap in the
  data.

The values are carried inside the case rather than left to be fetched from the two reports, for the
same reason the spectrogram's image is built from its own buffer: **a consumer that displays values the
comparison did not judge can display something the comparison contradicts.** The cost is a few
duplicated scalars; the guarantee is that the verdict and the evidence for it cannot drift apart.

### 3. `different` has no direction, and cannot acquire one

`different` carries the two values and **nothing else**. It has no ordering, no delta, no ratio, no
"higher", no "lower", no "improvement", no "regression", no winner. The comparison type SHALL NOT
conform to `Comparable`, SHALL NOT expose a preferred side, and SHALL NOT expose any operation that
reduces the pair to one of its members.

The order of the two sides is **the order the user supplied them** — the file already open, then the
file chosen for comparison. That order exists so a surface can label two columns. It carries no rank,
and the domain SHALL derive nothing from it.

### 4. Only `available` against `available` is comparable

Comparison is defined **only** when both sides are `available`. Every other combination is
`incomparable`.

`uncertain` is explicitly included in that exclusion, and this is the consequential half of the rule.
ADR-0008 defines `uncertain` as *read but not reliable*. Comparing an unreliable reading against
anything and reporting "same" or "different" would present an unreliable value as a comparable fact —
the precise failure mode invariant #1 exists to prevent.

**A deliberate and possibly surprising consequence, recorded so it is not later "fixed":**
`estimatedBitrate` is `uncertain` by construction (ADR-0012 keeps it always-uncertain), so two files
will essentially always compare as `incomparable` on that field. That is correct. The two estimates are
still shown side by side, because they are on their own reports; what the system declines to do is
assert a relationship between two numbers neither of which it trusts.

### 5. `incomparable` explains itself structurally, and never collapses to "missing"

The gap SHALL carry **the state of each side** — `available`, `unavailable`, `unsupported`, `uncertain`
or `failed` — so every combination is distinguishable: one side absent, the other side absent, both
absent, one unsupported against one available, an extraction failure against a clean read, and so on.
Collapsing these into a single "not available" would discard the difference between *"this format
cannot express bit depth"* and *"reading bit depth errored"*, which are different things to tell a
person and are already distinct one level down.

The state enumeration this needs includes `available`, and therefore **cannot** be `WarningKind`, which
deliberately excludes it so that a contradictory warning is unrepresentable. The two types are
different on purpose and are not to be unified.

### 6. Duration is compared exactly, and only as a technical fact

Duration is compared **exactly**. No epsilon, no millisecond tolerance, no percentage, no
frame-equivalence, no alignment.

A tolerance is not a smaller version of exact comparison; it is a **different question** — *"could
these be the same recording despite small differences?"* — and answering it requires alignment,
silence compensation and offset estimation, all of which are heuristics that belong to a later
evidence-level comparison. Introducing a tolerance here would answer that question implicitly, with an
undeclared threshold, inside a comparator that claims to state technical facts.

What is compared is therefore **the declared or observed technical fact**, not musical identity. Two
files of the same recording that differ by one frame compare as `different`, and that is the honest
answer to the question actually being asked.

### 7. Declared and estimated bitrate remain different facts

`declaredBitrate` and `estimatedBitrate` are compared **only against their own counterpart**. A
declared rate on one side SHALL NEVER be compared against an estimated rate on the other. ADR-0008
already keeps them separate fields precisely because they are not measurements of the same thing, and
comparing across them would silently undo that decision.

### 8. Warnings and status are context, not comparable properties

Warnings and the global inspection status are presented **side by side** and are **not** run through
the comparison. A warning is contextual evidence about how one report was produced; two files both
`partial` for entirely different reasons are not "the same", and reporting them as such would be a
false equality. Two files with an identical warning code are not thereby equivalent either.

### 9. What this MVP excludes, and why the exclusions are decisions

- **Byte hashes.** Objective and cheap, but they answer *"same file"* while inviting the reading *"same
  audio"* — false in both directions, since identical audio with different tags hashes differently.
  Excluded until there is a surface that can state what a hash does and does not mean.
- **Signal comparison** — waveforms and spectrograms side by side. Both models already exist and are
  already on an absolute, un-normalised scale *because* the user compares copies. They are deferred to
  their own change so that the property semantics above are settled first, not because they are hard.
- **Evidence comparison** — alignment, gain matching, residual, correlation, spectral difference. Every
  step is a heuristic with a threshold tied to an engine version, and none of the metrics it would
  compare exist yet.
- **Export.** The `schemaVersion` 1 contract describes **one** file; `inspectedFile` is singular and
  that singularity is part of its meaning. No comparison field is added to it and **no second
  `inspectedFile` will ever be added**. A comparison export, if it happens, is a separate document kind
  with its own version that composes two v1-shaped payloads — designed when there are comparisons worth
  exporting, not before.

## Alternatives considered

- **`Bool` — same or different.** The obvious shape. Rejected: it has no room for "nothing was
  compared", so an absent property becomes "different" and the feature manufactures facts from gaps.
  This is ADR-0008's rejected `{ state, value?, note? }` struct in a new costume.
- **`Bool?` — with `nil` for "cannot compare".** Rejected: it collapses every reason into one. It
  cannot distinguish *unsupported* from *failed* from *one side absent*, which is the distinction the
  domain already pays for one level down.
- **A similarity percentage or difference score.** Rejected outright by invariant #3. "87 % similar" is
  the prohibited aggregate score with a different label, and it would be the first thing anyone read.
- **An ordered comparison — better/worse, or `Comparable`.** Rejected by invariants #1 and #4. There is
  no field on which higher is honestly better: 24/96 is not better than 16/44.1, and the product exists
  to stop saying so.
- **Carrying both original `Property` values inside `incomparable`.** Loses nothing and needs no new
  type, but re-embeds reasons and failure messages the two reports already carry, turning the
  comparison from a judgement into a wrapper. Rejected in favour of carrying only the two **states**.
- **Carrying no values at all**, with the surface reading them from the reports. Smaller, but lets the
  displayed values and the judgement drift apart. Rejected for the same reason the spectrogram's image
  is built from its own buffer.
- **A duration tolerance now.** Rejected for this MVP and **deferred**, not dismissed: it belongs with
  alignment, where the question it answers can be asked out loud.
- **Hashing now.** Deferred, as above.

## Consequences

### Positive

- The honesty invariants are structural rather than conventional: with no ordering, no score and no
  reduction to one side, a verdict has nowhere to live even if someone later wants one.
- `incomparable` being first-class means the most common real case — two files of different formats —
  is described accurately instead of being forced into a same/different frame that does not fit it.
- The comparison needs **no port, no adapter, no framework and no I/O**: it is a pure function of two
  reports the app already produces. The layer boundaries are unaffected.

### Negative / costs

- Three cases and a structured gap are more to write and to test than a `Bool`, and every consumer must
  handle `incomparable` explicitly.
- Comparing files of different formats will yield many `incomparable` results. That is honest and may
  read as unhelpful; the surface has to make an absence of comparison legible rather than look broken.
- `estimatedBitrate` never comparing is a real usability cost, accepted deliberately in §4.

### Neutral

- Establishes the `same / different / incomparable` vocabulary for any future comparison, including the
  visual and evidence levels, which will need the same three-way answer with confidence added.

## Follow-ups

- **Promotion criteria** (see Status): the comparison implemented against production code, and its
  surface validated by a person. Until then this ADR asserts a direction, not a proven result.
- The visual comparison (waveforms and spectrograms side by side) is a separate change and may reuse
  this vocabulary; it must not weaken it.
- If a comparison export is ever wanted, its document kind and version are decided in a record of their
  own, and never by extending `schemaVersion` 1.
