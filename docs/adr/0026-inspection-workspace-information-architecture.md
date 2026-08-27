# ADR-0026: The inspection workspace — one file, five sections, and a comparison that is a mode

- **Status**: **Proposed.** It stays Proposed until the navigation contract is implemented against
  production code and demonstrated by tests that fail when it is broken: the selected section reachable
  from no target below the composition root, a new primary file returning to Overview, and a comparison
  neither changing the section when it starts nor when it ends. Partial evidence does not promote it.
  The manual validation of the resulting surface belongs to the redesign's **final** slice, not to this
  record — see **Promotion conditions**.
- **Date**: 2026-08-27
- **Deciders**: Project maintainer
- **Related**: **ADR-0024** and **ADR-0025** (whose refusals this record inherits and **must not
  weaken** — *referenced, never edited*), **ADR-0017** (comparison semantics, still `Proposed`),
  ADR-0005 (module structure), ADR-0009, ADR-0018 (where a value may live — the ownership question, one
  layer down), `docs/vision.md`, capability `audio-two-file-comparison`, change
  `restructure-inspection-workspace`

## Context

Everything the app knows about a file arrives on **one scrolling page**. Waveform, spectrogram, eight
property rows, four measurements, warnings, the global status, and — when a second file is chosen — a
comparison block underneath all of it. Each piece was added where the previous one ended, which was
right each time and is now the whole problem: the page has no first thing to read, no way to go
somewhere, and no shape that says which file is the subject.

Three facts about the product decide the answer, and none of them is new:

- **The primary act is inspecting one file.** Comparison is something a person asks for *while*
  looking at a file, against the file they are already looking at. It is not a second document.
- **There is no collection.** No history, no library, no recents, no persistence beyond an inspection
  (ADR-0004 defers persistence; ADR-0010 keeps access to the length of one inspection). Nothing exists
  to browse.
- **A reader needs a quick read first, and depth on request.** `docs/vision.md` §5 already requires
  *"a plain-language summary and a technical view"* for every result. One page delivers neither: it
  delivers both at once, in the order they were built.

**What this record is not.** It decides structure and ownership. It fixes no colour, no spacing, no
type scale, no SwiftUI type and no layout. Those belong to the slices, and a decision that cannot
outlive a redesign of its own spacing does not belong in an ADR.

## Decision

### 1. A window inspects **one primary file**, and that is the whole of its subject

The window's subject is the file most recently inspected. There is no list of past inspections, no
recents menu and no library, because none of them exists in the domain to show. A second file appears
only as a comparison **against** the primary one, and leaves without disturbing it.

### 2. Three high-level states, and a comparison is **not** a fourth document

```
Empty ──select──► Inspection(A) ──Compare…──► Inspection(A) + Comparison(A ↔ B)
                        ▲                                   │
                        └──────── Close comparison ─────────┘
```

`Comparison` is a **mode of the same workspace**, not a document of its own. A is still the file being
inspected throughout; B is contextual and temporary. This is the shape `ImportFlowModel` already has —
`state` for the inspection, `comparison` beside it — and this record adds no state to it.

### 3. Five sections, the same five in both modes

**Overview · Measurements · Waveform · Spectrum · Details.**

The same five areas exist whether or not a comparison is settled; what changes is **what each one
contains**, not which ones there are. A person who was reading the Waveform section before starting a
comparison is still reading the Waveform section afterwards.

**"Spectrum" is a navigation label, not a rename.** The artefact is a spectrogram, the capability is
`audio-two-file-visual-presentation`, and `SpectrogramCopy.title` is unchanged. Sections are named for
where a reader is going; the drawing keeps the name it has everywhere else.

### 4. The selected section is **presentation state**, owned by the composition root

It is not a domain value, not a field of `ImportFlowModel`, not part of `ComparisonState`, not part of
`InspectionPresentation`, and not persisted. It answers *"where is this person looking"*, which is a
fact about a window and about nothing else.

The test is ADR-0018's, applied one layer up: a value belongs where the thing it describes lives. The
report, the analyses and the comparison describe **a file**; the selected section describes **a
reader**. Putting it in the flow would make the flow's own stale guards, cancellation and operation
numbers responsible for something no operation produces.

**No target below the composition root may name it.** `AudioInspectorDomain`, `FeatureImport` and
`FeatureAnalysis` stay unable to observe which section is selected — asserted, not intended.

### 5. Its whole lifetime, in four rules

| Event | The selected section |
| --- | --- |
| a **new primary file** is inspected | returns to **Overview** |
| a comparison **starts** | **unchanged** |
| a comparison **ends** — dismissed, superseded, or the primary replaced | **unchanged**, except where the primary was replaced, which is the row above |
| the app **launches** | **Overview**; nothing is restored |

**Nothing else moves it.** No result, no failure, no absence and no arrival of a measurement changes
where a person is looking. A section that jumped when an analysis settled would take the window away
from the reader mid-sentence, and a surface that navigates itself is a surface that cannot be trusted
to stay still.

**It never participates in a stale guard.** Operation numbers exist to stop one inspection's result
landing beside another's; a section selection belongs to no operation and is never checked against one.

### 6. What the Inspection Overview may contain

Facts the app already holds, and nothing derived from them by reasoning:

| Element | Class | Permitted |
| --- | --- | --- |
| the file's identity — name, extension, size, modified date | factual, already held | **yes** |
| core technical facts — container, codec, rate, depth, channels, duration | factual, already held | **yes** |
| the inspection's own result state — completed, partial, failed | factual, already held | **yes** |
| key measurements, in the words `audio-two-file-comparison` and ADR-0022/0023 already fix | factual, already held | **yes** |
| a **compact waveform**, reusing the envelope already produced | factual — the same artefact, no second read | **yes** |
| the **number of warnings**, as a way in to Details | derived, presentation-only | **yes, under §7** |
| a plain-language summary of what the file *is* | inferential | **no** |
| any score, grade, rating or "quality" | inferential | **no** — `docs/vision.md` §2 |
| any statement about origin, master, transcode or upsample | inferential | **no** — Findings' |
| a judgement of any value as good, bad, high or low | inferential | **no** — `audio-file-inspection` |

### 7. The warning count is permitted, and the three conditions that keep it a fact

A number is a summary, and this record refuses summaries — so this one is argued rather than assumed.
It is permitted **only** when all three hold:

1. it is the **cardinality of a list the report already carries and the reader can open**, not a value
   computed about the audio;
2. it appears **only about one file's own report**, never about a comparison — a count over a
   comparison is what `audio-two-file-comparison` forbids, and §8 keeps that boundary absolute;
3. it is presented as **navigation**, never as a signal: no colour that varies with it, no threshold,
   no wording implying that more is worse or that zero is good.

If any of the three cannot be held, the count goes and the section title carries the reader instead.

### 8. What the **Comparison** Overview may contain — and it is deliberately very little

| Element | Source | Permitted | Reason |
| --- | --- | --- | --- |
| First file's identity | `FileComparison.first.file` | **yes** | a fact, already shown |
| Second file's identity | `FileComparison.second.file` | **yes** | a fact, already shown |
| each side's basic identifying facts | the two reports | **yes** | already shown, per file, uncompared |
| the existing factual framing — *"Shown for context, not compared"* and its siblings | `ComparisonCopy` | **yes** | already canonical wording |
| a way through to the full comparison | navigation | **yes** | not a statement about the files |
| a count of `same` | — | **no** | an aggregate over the comparison |
| a count of `different` | — | **no** | an aggregate over the comparison |
| a count of `incomparable` | — | **no** | an aggregate over the comparison |
| a percentage or similarity | — | **no** | a score by another name |
| a filtered *"properties that differ"* list | — | **no** | see below |
| a summary verdict, "match", or "these are the same" | — | **no** | the prohibited phrase itself |
| *"important differences"* or any editorial ordering | — | **no** | an inference about which facts matter |
| a confidence | — | **no** | Findings' machinery |
| which file is better, or which to keep | — | **no** | ADR-0017 §1, ADR-0024 §1 |

**Why the filtered list is refused, and it is not the obvious reason.** A list of *properties that
differ* publishes no count, no score and no ordering while it has rows, and on that reading it survives.
It does not survive its **empty state**: a differences list that renders empty says *the two files
match*, which is precisely what `audio-two-file-comparison`'s own scenario refuses —

> **WHEN** every comparable measurement agrees **THEN** the system offers no single value, flag or
> phrase meaning "the two files match"

— and no wording of that empty state escapes it, because the emptiness *is* the statement. The list
would therefore be correct in every case except the one a person most wants an answer to, which is the
worst possible place to be wrong.

**This specialises the capability; it does not weaken it.** Every prohibition above is already in force.
What this record adds is that the *absence of rows* can carry the aggregate as surely as a number can,
so the Comparison Overview is built with no place for rows to be absent from.

### 9. Waveform and Spectrum are **workspaces**, and gain no powers

A section gives each drawing room. It gives it nothing else: **no zoom, no cursor, no scrubbing, no
playback, no selection, no synchronised navigation, no alignment, no difference view.** The models are
unchanged, the absolute scales are unchanged, the paired presentation is unchanged, and
`SpectrogramColourRamp` is unchanged. `waveform-visualization` and
`audio-two-file-visual-presentation` both forbid interaction, and a bigger area is not an argument for
acquiring some.

When a comparison is settled, these sections carry the **paired** drawings, which already stand in for
the single ones (`audio-two-file-visual-presentation`). The redesign moves where that happens; it does
not change whether it happens.

### 10. Details holds what the other four do not

Secondary metadata, the per-property availability and certainty detail, the warnings and notes
themselves, the global inspection status, and the export action's context. It is where a reader goes to
see everything, and it is the reason the other sections may be short.

### 11. Progressive disclosure hides explanation, never fact

A method line, a resolution, a reason, a limitation may be **collapsed** — reachable in a click and
never removed. What may not be hidden: a value, its unit, an absence, a failure, a certainty state, or
any sentence a capability requires. Collapsing is a way to fit an explanation on a screen, not a way to
stop making one.

Nothing collapsed may be unreachable to an assistive reader, and `audio-file-inspection` §"Present the
report in human terms" is inherited entire: each property still reachable as one coherent element, no
meaning by colour alone, legible at accessibility text sizes.

### 12. No sidebar, and this is where it disagrees with `docs/vision.md`

`docs/vision.md` §7 names `NavigationSplitView` among the marks of "a real macOS utility". **This record
does not adopt it, and says so rather than quietly diverging.**

A split view's sidebar exists to navigate a **collection** — documents, mailboxes, a library. This app
has one file at a time and keeps nothing, so a sidebar would list either one row or five section names
that are not documents. The principle vision.md is actually stating is *be native rather than a scaled-up
iPhone UI*, and the native answer for a single-subject window is a **toolbar and section navigation**,
not a sidebar over an empty collection.

`docs/vision.md` is the product record and is **not edited here**. If a collection ever exists —
persistence (ADR-0004), batch (roadmap Phase 2) — the question reopens, and a sidebar becomes the
obvious answer rather than a borrowed one.

The toolbar may hold window-wide actions. **Which** actions, and where, is a slice's decision.

## Alternatives considered

- **Keep the single scrolling page and only reorder it.** Cheapest, and it changes nothing about the
  two real problems: there is still no first thing to read, and a comparison still arrives as more page
  below what was already too long. Rejected — reordering a list that has no entry point produces a
  differently ordered list with no entry point.
- **A `NavigationSplitView` with a sidebar.** The native idiom `docs/vision.md` names, and the reason it
  is refused is §12's: a sidebar navigates a collection, and there is none. Rejected now, and named as
  the obvious answer if persistence or batch ever creates one.
- **Section selection inside `ImportFlowModel`.** One state holder, one place to look. Rejected: it puts
  a fact about a reader inside the type that owns operation numbers, cancellation and stale guards, and
  the first bug would be a section that changed because an analysis settled.
- **Routes, or any persisted navigation.** Restoring the last section across launches sounds helpful and
  is not: the file is gone, so the section would be restored over an Empty state, and the app would open
  somewhere the reader never chose. Rejected; §5 launches at Overview.
- **A comparison-first application** — two files as the primary act. Rejected by the product decision
  and by the domain: `FileComparison` is derived *from the report on screen*, and every stale guard in
  the flow exists because a comparison is against a primary file.
- **A separate view per mode, each with its own lifecycle.** Clean-looking, and it duplicates every
  transition: two places to reset a section, two places to publish a pair, two ways to be stale.
  Rejected — the mode is a mode, and `ComparisonState` already models it.
- **Leaving the comparison buried at the bottom of Details.** The smallest change, and it keeps the
  thing a person explicitly asked for below everything they did not. Rejected.
- **An Overview that summarises the result** — a verdict line, a grade, a "looks fine". Rejected by
  `docs/vision.md` §1–2, by `audio-file-inspection`'s presentation requirement, and by every ADR from
  0017 to 0025. It is the single most likely thing to be asked for and the single thing this product
  exists not to do.
- **A filtered differences list in the Comparison Overview.** Considered seriously and rejected on its
  empty state alone (§8), not on principle — which is why the refusal is written out rather than
  asserted.

## Consequences

### Positive

- **A window has a first thing to read.** Overview is an entry point rather than the top of a scroll.
- The section list is the same in both modes, so a comparison **adds content without moving the
  reader** — the property §5 exists to protect.
- **No new lifecycle.** `ImportFlowModel` and `ComparisonState` remain the only sources of truth about
  data; navigation adds a value that no operation produces and no guard consults.
- Each section becomes a place a slice can be delivered into, so the redesign can land in small PRs
  instead of one.
- The Comparison Overview's smallness is **derived from an accepted requirement** rather than chosen,
  so it cannot drift back toward a summary without contradicting a promoted capability.

### Negative / costs

- **The Comparison Overview is thin**, and it will look thin. A person opening it learns which two
  files are being compared and nothing else, and has to go to Measurements or Details for anything
  substantive. That is the honest cost of refusing the summary, and it is paid deliberately.
- **Five sections is more navigation than one page**, and something a reader could previously see by
  scrolling now takes a click. The compact waveform in Overview mitigates this for the one artefact
  most likely to be wanted at a glance; nothing mitigates it for the rest.
- **Every section is a place to get the copy wrong**, and the surface area for a forbidden word grows
  with it. The existing vocabulary sweeps cover the paired surface only.
- **This is a large redesign of a working app** delivered over several slices, and the intermediate
  states are real: between R1 and R9 the app has a section shell whose sections are not all filled.
- **It diverges from a written product principle** (§12), which is a cost even when argued.

### Neutral

- No domain type changes, no port changes, no module boundary moves, no export change, and
  `schemaVersion` stays 1.
- The capabilities that govern what each section *contains* are untouched. This record governs where a
  reader is, not what is true.

## Promotion conditions

**Automated — each must fail when the property is broken.**

1. **Ownership.** No target below the composition root names the selected section; asserted over all of
   `Sources/`, in the shape `SharedPCMDecodeCountTests`' source assertion already uses.
2. **A new primary file returns to Overview**, whatever section was selected.
3. **A comparison starting does not move the reader**, from every section.
4. **A comparison ending does not move the reader** — dismissed, superseded, or the second file failing.
5. **Nothing else moves it**: an analysis settling, failing or arriving absent leaves the section alone.
6. **No persistence.** The section is not written anywhere that survives a launch.
7. **The Comparison Overview publishes no aggregate**, direct or by absence: a vocabulary sweep over
   every string it can render, in every state, including two files whose comparable measurements all
   agree — the case §8 refuses.
8. **The semantics below are unchanged**: the measurement comparison, the paired presentation and the
   export produce exactly what they produce today.

**Manual — none in this record, and that is a decision.** ADR-0025 required two human checks because its
subject was a *drawing*, where a property could be true in arithmetic and invisible on screen. This
record's subject is **structure and ownership**, and every claim above is a value a test can read. The
question a person must answer — *can someone open an inspection, know where to start, and enter and
leave a comparison without losing their place* — is about the finished surface, not about this decision,
and it belongs to the redesign's final slice. Requiring it here would block a structural record on a
surface that does not exist yet.

## Follow-ups

- **The change is `restructure-inspection-workspace`**, which carries the slice map and the contracts
  that must survive it. This record decides; that change sequences.
- **`docs/vision.md` §7 is left as it stands.** §12 records the divergence and the condition under which
  it ends; editing the product record to match an architecture decision would be the wrong direction.
- **Persistence, batch and history remain out** (ADR-0004, roadmap Phase 2). If they arrive, §1 and §12
  are the two decisions to revisit, in that order.
- **Findings and evidence comparison are untouched** and nothing here authorises either. An Overview is
  the most tempting place a verdict could appear, which is why §6 and §8 enumerate rather than gesture.
