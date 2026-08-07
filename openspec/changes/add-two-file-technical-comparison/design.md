# Design — two-file technical comparison

Everything below was contrasted against the real code before it was written. Where a decision is
already recorded in **ADR-0017**, this document states the shape rather than re-arguing it.

## 1. The one question, and the ones it refuses

**Answers:** *which observable technical facts are the same, different, or not comparable between these
two files?*

**Refuses, explicitly and as non-goals:** are these the same recording · does one derive from the other
· which has more quality · which should I keep · is it fake · is it a transcode · what percentage
similar are they.

The first list is answerable from data the app already produces. The second needs alignment,
heuristics, thresholds and metrics that do not exist — and two of its entries are verdicts the product
forbids at any level of evidence.

## 2. Comparison semantics

Three cases, exhaustive, in the shape ADR-0008 established for a single property:

- **`same(Value)`** — both sides `available`, values equal by the field's own exact criterion.
- **`different(first: Value, second: Value)`** — both sides `available`, values unequal.
- **`incomparable(ComparisonGap)`** — every other combination.

**Naming, contrasted with the domain's real style.** The existing vocabulary is adjectival —
`available`, `unavailable`, `unsupported`, `uncertain`, `failed`, `completed`, `partial` — so `same`,
`different` and `incomparable` fit and `differs` (a verb among adjectives) does not. The type name
follows `Property<Value>`: **`PropertyComparison<Value>`**, generic, with conditional `Sendable` and
`Equatable` exactly as `Property` has them.

**Why the values are carried inside the case.** They could be fetched from the two reports instead,
which would be smaller. They are carried because a surface that displays values the comparison did not
judge can display something the comparison contradicts — the same reason `SpectrogramRaster.image(for:)`
is built from its own `buffer(for:)` rather than re-deriving the layout. The cost is a few duplicated
scalars.

**`different` carries the two values and nothing else.** No delta, no ratio, no ordering, no
`Comparable` conformance, no accessor that returns "the better one". The absence is structural: a
verdict has nowhere to live.

## 3. `incomparable`, and why it needs a type

The gap carries **the state of each side**, so every combination stays distinguishable:

```
PropertyState: available | unavailable | unsupported | uncertain | failed
ComparisonGap: (first: PropertyState, second: PropertyState)
```

Three consequences worth stating out loud.

**It cannot be `WarningKind`.** That enum deliberately omits `available` so a contradictory warning is
unrepresentable. The gap *needs* `available`, because "one side available, the other unsupported" is
one of the most common real outcomes. The two types are different on purpose; a later "unification"
would break one of them.

**`ComparisonGap` is a type rather than two loose parameters, for one reason only:**
`incomparable(available, available)` would be a contradiction, and leaving it representable would give
up exactly the guarantee ADR-0008 buys. So the gap has a **failable initialiser that refuses two
`available` states** — the same device `WaveformBucket.init?` uses to refuse a bucket it could not
describe honestly. Without that, a smaller shape would have been correct.

**Only `available` against `available` is comparable**, `uncertain` included in the exclusion. ADR-0017
§4 carries the argument. The consequence to expect in practice: **`estimatedBitrate` will essentially
always be `incomparable`**, because the reader marks it `uncertain` by construction. Both numbers are
still on screen, from their own reports; what the system declines to do is assert a relationship
between two values neither of which it trusts.

## 4. Which fields the MVP compares

**A finding first: there is no `format` property.** `TechnicalProperties` holds `container` and `codec`
as separate fields, and the project treats the distinction as load-bearing — `container` is an
*extracted technical property* precisely because it can be uncertain or fail. Nothing is lost; there is
simply no field to compare under that name.

**The comparison covers exactly `TechnicalProperties`, and nothing else.** That is the whole rule:
extracted technical properties are compared; everything else is shown, not judged.

| Field | Decision | Why |
| --- | --- | --- |
| `container` | **Compared**, exact token equality | An extracted technical property |
| `duration` | **Compared**, exact | §5 |
| `sampleRate` | **Compared**, exact | |
| `channelCount` | **Compared**, exact | |
| `bitDepth` | **Compared**, exact | Frequently `unsupported` on one side — the case the whole design exists for |
| `codec` | **Compared**, exact token equality | |
| `declaredBitrate` | **Compared**, exact, **only against `declaredBitrate`** | §6 |
| `estimatedBitrate` | **Compared**, exact, **only against `estimatedBitrate`** | Uniform rule; in practice always `incomparable` (§3) |
| `fileExtension` | **Shown side by side, not compared** | File metadata, not an extracted property. `container`/`codec` are the technical facts; an extension is a filename convention |
| `sizeBytes` | **Shown side by side, not compared** | Objective but near-empty: two files of the same audio differ in size for tags, padding and container overhead. "Different" would be true and uninformative, while inviting *smaller = worse* |
| `modifiedAt` | **Excluded** | The report itself labels it *file metadata, not forensic evidence* |
| `displayName` | **Excluded** | Two names differing means nothing |
| `source` | **Excluded** | Both are user-selected local files; there is nothing to compare |
| `id` | **Excluded, and cannot be used** | §7 |

`fileExtension` and `sizeBytes` are also the two entries a reviewer could reasonably want moved — see
open question 1.

## 5. Duration is exact

Exactly equal, or `different`. No epsilon, no milliseconds, no percentage, no frame-equivalence, no
alignment. ADR-0017 §6 records why: a tolerance answers *"could these be the same recording?"* with an
undeclared threshold, inside a comparator that claims to state technical facts.

`duration` is a `Double` of seconds, so **exact means exact `Double` equality**, and two files of the
same recording that differ by one frame compare as `different`. That is the honest answer to the
question actually being asked — this compares the **declared or observed technical fact**, never
musical identity.

## 6. Declared and estimated bitrate stay apart

Each is compared **only against its own counterpart**. A declared rate on one side is never compared
against an estimate on the other. They are separate fields because they are not measurements of the
same thing, and crossing them would silently undo that decision while looking like a convenience.

## 7. A and B: order without rank

The domain names the two sides **`first` and `second`** — the order the user supplied them, the file
already open and then the file chosen for comparison. That order exists so a surface can label two
columns; the domain derives nothing from it, and no operation reduces the pair to one member.

The **surface** may say *current file* and *comparison file*, which is presentation language and stays
in the feature layer.

**`AudioFileReference.id` cannot serve as identity here, and the reason matters.** It is a `UUID`
generated **per inspection**, documented as implying no stable identity across sessions. Two
consequences:

- a comparison cannot be persisted or recovered by it — it would not survive a relaunch;
- **it cannot detect the same file being chosen twice.** Inspecting one file twice yields two different
  `id`s. The MVP therefore does **not** detect that case and does not try: it compares the file with
  itself honestly, every technical property comes out `same`, and nothing is claimed beyond that. Any
  detection would have to match on name, size and date — a heuristic, and out of scope.

## 8. Warnings and status are context

Both reports' warnings and global status are shown **side by side and are not compared**. Two files
both `partial` for entirely different reasons are not "the same", and reporting them as such would be a
false equality; two files sharing a warning code are not thereby equivalent. They explain **why** a
property is incomparable, which is their whole usefulness here.

A useful property of this choice: a **globally failed** second file needs no special case. Its report
exists with `.failed` status and all-`unavailable` properties, so the comparison is constructible and
comes out **entirely `incomparable`** — and the status shown beside it says why. Nothing has to detect
the failure; the semantics already describe it.

## 9. `FileComparison`

A pure value object: the two reports, plus one `PropertyComparison` per compared field.

- **No lifecycle, no identity, no aggregate root.** A comparison is derived data, not an entity.
- **No score, no winner, no confidence.** Confidence belongs to inference; this states facts.
- **No count of differences exposed as a measure.** A number of differing fields is an aggregate score
  in disguise the moment a surface renders it as one.
- **Deterministic** — the same two reports always produce the same comparison.
- **`Sendable` and `Equatable`**, which every component type already is.
- The two reports are **held whole rather than copied field by field**: the surface needs each file's
  own facts, warnings and status anyway, and duplicating them would create a second copy that can drift
  from the first.

## 10. A pure operation, not a use case

**`CompareInspectionsUseCase` should not exist.**

`InspectAudioFileUseCase` earns its name: it orchestrates a **port**, catches a typed throw and turns a
global failure into a report. A comparison has no port, no I/O, no failure mode and nothing to
orchestrate — two valid reports always yield a valid comparison. Creating a use case here would be an
abstraction built for symmetry, which is precisely what this project refused when it declined to create
`SpectrogramGenerating` for having one implementer and one consumer.

The shape is therefore **an initialiser on `FileComparison`** taking two reports: not `async` (nothing
suspends), not `throws` (nothing fails), not failable (no input is invalid). It matches
`WaveformBucket` and `SpectrogramGridMapping`, which are plain domain types.

**Reversal criterion**, in the manner the spectrogram slice used: introduce a use case if comparison
ever needs to orchestrate something — re-reading a file, consulting a port, or failing.

## 11. The flow

Start: report A is on screen. Action: **Compare with another file…**. Then B is chosen through the
**existing** selection path and inspected by the **existing** pipeline, unchanged.

**The one real change to the flow's semantics.** Today every new selection *supersedes* the previous
one: `ImportFlowModel` holds a single operation number and a newer result replaces an older one. A
comparison needs a second inspection that **does not supersede the first**. That is a genuine change to
what the flow means, not a new branch in it, and it is where the risk in this slice sits.

| Case | Behaviour |
| --- | --- |
| B cancelled | A untouched, no comparison, back to A alone — the neutral restore the flow already performs |
| B fails globally | The comparison is shown and is entirely `incomparable`; B's failed status explains it (§8) |
| B chosen while A's visualisations are still running | A's waveform and spectrogram operations continue and are **unaffected**; they are already independent operations with independent cancellation |
| Another file C chosen for comparison | Replaces B, keeps A |
| A stale B result arrives | Dropped. B needs its **own** operation identity, disjoint from A's |
| A chosen again as B | Compared honestly; every property `same` (§7) |
| Dismissing the comparison | A remains exactly as it was |
| Security scope | Two **sequential** windows, each opened and closed by its own inspection's `defer` (ADR-0010). Nothing is held across them; only the reports are kept |

## 12. Deferred, on purpose

**Visual comparison** → its own change, `add-two-file-visual-comparison`: waveforms and spectrograms
side by side, on the same absolute scale, with compatible axes. Both models exist and are **already
built for this** — `Spectrogram`'s own contract says its scale is absolute and never normalised
*because the user compares copies of the same music*. It is deferred so the property semantics are
settled first, not because it is hard.

**Export** → out of scope entirely. `schemaVersion` 1 stays **byte-identical**: no comparison field
enters it, and **no second `inspectedFile` will ever be added to it** — that document describes one
file, and the singularity is part of its meaning. If a comparison export is ever wanted it is a
separate document kind with its own version, composing two v1-shaped payloads, decided in its own
record.

**Evidence comparison** — alignment, gain matching, residual, correlation, spectral difference — waits
for the metrics it would compare to exist.

## 13. Open questions

1. **`fileExtension` and `sizeBytes`: shown or compared?** §4 shows them without comparing, on the
   grounds that they are file metadata and that size differences are expected and uninformative. A
   reasonable reviewer could want `fileExtension` compared. Decide before group 2.
2. **Exact `Double` equality for duration** is what "no tolerance" means literally. Confirm that is
   intended rather than "equal to the precision the reader reports".
3. **Does the comparison surface replace the report view or sit beside it?** Affects group 4's shape,
   not the domain.
4. **Are A's waveform and spectrogram still shown while comparing?** They are unaffected either way
   (§11); this is a presentation decision.
