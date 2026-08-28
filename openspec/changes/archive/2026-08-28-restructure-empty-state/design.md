# Design — the surface before a report, read off production first

Everything below starts from the code as it is. Where this document and the capability disagree, the
capability is right; where it and ADR-0026 disagree, the ADR is right.

## 1. What production actually does today

`RootView` switches on `flow.state`: `.idle`, `.working` and `.failed` all render `ImportFlowView`;
`.report` renders the workspace R1 built. The drop destination and the drop overlay sit on the **whole
window**, in every state, outside that switch.

### `.idle`

| | |
| --- | --- |
| renders | `Audio Inspector` (title2) · one sentence (callout, secondary, centred) · `Choose audio file…` button |
| actions | the button → `selectAndInspect()` |
| picker | `NSOpenPanel`, `allowedContentTypes = [.audio]`, single file, no directories, aliases resolved |
| drop | whole window; `DroppedSource.evaluate` decides |
| layout | `VStack(spacing: 12)`, `padding(40)`, `maxWidth/.maxHeight: .infinity` |
| accessibility | whatever `Text` and `Button` give by default; nothing declared |

### `.working`

| | |
| --- | --- |
| renders | the same title and sentence, the button **disabled**, and an indeterminate `ProgressView` |
| second operation | impossible: `inspect(using:)` opens with `guard state != .working else { return }` |
| drop | refused with `DropRejection.inspectionInProgress` — *"Wait for the current inspection to finish."* |
| cancellation | **none of the inspection.** `ImportFlowModel` exposes no cancel; dismissing the open panel yields `.cancelled`, which restores the previous state |
| progress | **indeterminate only.** No `fractionCompleted`, no `totalUnitCount`, no phase count exists anywhere in `Sources/` |
| file name | **not available.** `case working` carries no payload |

**`.working` begins before a file has been chosen.** `selectAndInspect()` sets `.working` and *then*
awaits the panel, so the state spans both choosing and reading. Nothing in the state distinguishes the
two, which is why §5 refuses any wording that names the file or the phase.

### `.failed`

| | |
| --- | --- |
| meaning | `preparationFailed` only — the selection could not be turned into an inspectable file at all |
| renders | the same title and sentence, the message in **red**, the button relabelled `Try again` |
| message | `"That file could not be opened for inspection."`, supplied by `ImportFlowModel` |
| the button | calls `selectAndInspect()` — the **same** action as idle. It is not a retry |
| retry | impossible: no URL and no bookmark is retained (ADR-0010, ADR-0013) |
| drop | still accepted; a valid drop starts a new inspection |

**A globally failed *report* is not this state.** A file that opens but cannot be read produces
`.report` with `status == .failed`, and is presented as a report. `.failed` here means only that no
inspection could be attempted.

### Drag and drop, in all three

Targeting shows *"Drop one audio file"* — instructive, never confirmatory, because macOS does not expose
the dragged items before the drop (ADR-0014). A rejected drop shows one of three sentences and **never**
becomes a flow failure. An accepted operation clears the notice; nothing else does.

## 2. Contracts this slice may not break

| Contract | Where it lives | Protected by |
| --- | --- | --- |
| Two mechanisms, one inspection path | `SourceSelection`, `DroppedSource`, `RootView.handleDrop` | `audio-file-inspection` §*Select a single local audio file*; `DroppedSourceInspectionTests` |
| Exactly one local file per operation | `DroppedSource.evaluate`, `panel.allowsMultipleSelection = false` | the same requirement; `DroppedSourceTests` |
| Supported types decided by the system, not a list | `allowedContentTypes = [.audio]`, `conforms(to: .audio)` | `DroppedSourceTests` |
| Security-scoped access held only for the operation | `SourceInspectionCoordinator` | the same requirement; ADR-0010, ADR-0013 |
| No URL, no bookmark, nothing persisted | coordinator + mapper | the same requirement; `ReadTemporaryMemoryTests` |
| The source is never modified | the whole read path | the same requirement |
| A drop while inspecting starts nothing | `DroppedSource.evaluate` | `ImportFlowDropTests` |
| A rejection is never a flow failure | `ImportFlowModel.reject` | `ImportFlowDropTests` |
| The three rejection sentences | `DropRejection.message` | `ImportFlowDropTests.everyRejectionHasItsOwnPresentableMessage` |
| Targeting states what is expected, never validity | `DropFeedbackOverlay` | the same requirement; ADR-0014 |
| Dismissing the panel is neutral | coordinator → `.cancelled` | `ImportFlowModelTests` |
| Stale guards and one inspection at a time | `ImportFlowModel` | `ImportFlowModelTests` |
| The failure sentence itself | `ImportFlowModel` | `ImportFlowModelTests`, `WorkspaceNavigationLifecycleTests` |
| Section navigation belongs to the report surface | `RootView.reportSurface` | R1's suites |
| One PCM read per inspection | the shared pass | `SharedPCMDecodeCountTests` |

**Nothing in the left-hand column is a layout decision, and this slice changes none of them.**

## 3. The problems, classified

| | Finding, from the code |
| --- | --- |
| **comprehension** | The purpose is stated, but as the head of a sentence whose tail is about drag and drop and file safety. It is legible, not prominent. |
| **hierarchy** | The largest element is `Audio Inspector`, which the title bar already says. The primary action is the smallest thing on screen. |
| **drop discoverability** | Stated in words, mid-sentence, at secondary weight. The window *is* the target; nothing shows where. |
| **trust** | The read-only promise is the last clause of the third line, and no test or requirement protects it. |
| **working** | A bare spinner. Nothing says an inspection is running, and the rest of the surface is unchanged, so the window reads as idle-with-a-spinner. |
| **error recovery** | The way out exists but is misnamed: `Try again` cannot retry. The message is red, and red is the only thing distinguishing it from body text. |
| **macOS** | Reasonable — a centred stack, no web idioms — but undifferentiated: three states that look alike. |
| **density / space** | `maxWidth: .infinity` with a centred paragraph: at 1600 pt the sentence becomes one very long line. There is no reading measure. |

## 4. The shell — four options, and the one production supports

| | Shape | Verdict |
| --- | --- | --- |
| **A** | one shell whose content varies by state | **chosen** |
| **B** | three separate surfaces | rejected — three places to keep the drop hint, the read-only line and the action in sync, and a visible rebuild on every transition |
| **C** | a permanent panel with a status strip beneath | rejected as a *distinct* option: it is A with the state region named, which is what A already becomes |
| **D** | a full-window drop zone containing the action | rejected — see §9; it shrinks the perceived target and duplicates the overlay |

**A**, and production already leans that way: `ImportFlowView` is one `VStack` with conditional members.
What this slice adds is that the constant part is genuinely constant — the purpose and the action do not
move, resize or reflow between states — and that the varying part is one region rather than three
insertions at three heights.

**The shell exists only while there is no report.** `RootView`'s switch is unchanged: `.report` renders
the workspace, and the shell is gone. It is not a state of the workspace and not a section of it.

## 4b. Wireframes

Structure only. No spacing, type scale or colour is decided here.

### Option A — conservative: today's stack, reweighted

```
┌──────────────────────────────────────────────┐   ┌──────────────────────────────────────────────┐
│                                              │   │ ╭ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ╮ │
│      Inspect a local audio file's            │   │ │   Inspect a local audio file's           │ │
│      technical properties.                   │   │ │   technical properties.                  │ │
│                                              │   │ │                                          │ │
│         [ Choose audio file… ]               │   │ │      [ Choose audio file… ]              │ │
│      Or drag one onto this window.           │   │ │   ╭───────────────────────╮              │ │
│                                              │   │ │   │  Drop one audio file  │              │ │
│  The file is only read, never modified,      │   │ │   ╰───────────────────────╯              │ │
│  moved or copied.                            │   │ │   moved or copied.                       │ │
│                                              │   │ ╰ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ╯ │
└──────────────────────────────────────────────┘   └──────────────────────────────────────────────┘
                    1. Idle                                     2. Drag targeted

┌──────────────────────────────────────────────┐   ┌──────────────────────────────────────────────┐
│      Inspect a local audio file's            │   │      Inspect a local audio file's            │
│      technical properties.                   │   │      technical properties.                   │
│                                              │   │                                              │
│         [ Choose audio file… ]  (disabled)   │   │   ⚠ That file could not be opened for        │
│              ◐  Inspecting…                  │   │     inspection.                              │
│      Or drag one onto this window.           │   │        [ Choose another file… ]               │
│                                              │   │      Or drag one onto this window.           │
│  The file is only read, never modified,      │   │  The file is only read, never modified,      │
│  moved or copied.                            │   │  moved or copied.                            │
└──────────────────────────────────────────────┘   └──────────────────────────────────────────────┘
                   3. Working                                     4. Failed
```

**Advantage** — smallest diff; nothing moves that does not have to. **Cost** — the state region is still
*inserted between* existing members, so the action and the trust line shift vertically as the state
changes; the eye loses its place on exactly the transitions that matter. **macOS** — idiomatic.
**Cognitive load** — low. **Scalability** — poor: a fourth state would be inserted at a fourth height.

### Option B — recommended: a stable frame with one state region

The purpose, the action and the trust line never move. Everything that varies happens in one reserved
region directly beneath the action.

```
┌──────────────────────────────────────────────┐   ┌──────────────────────────────────────────────┐
│                                              │   │ ╭ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ╮ │
│      Inspect a local audio file's            │   │ │   Inspect a local audio file's           │ │
│      technical properties.                   │   │ │   technical properties.                  │ │
│                                              │   │ │                                          │ │
│         [ Choose audio file… ]               │   │ │      [ Choose audio file… ]              │ │
│      Or drag one onto this window.           │   │ │   ╭───────────────────────╮              │ │
│  ┌ ─ state region — empty in idle ─ ─ ─ ┐    │   │ │   │  Drop one audio file  │              │ │
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘    │   │ │   ╰───────────────────────╯              │ │
│                                              │   │ │                                          │ │
│  The file is only read, never modified,      │   │ │  The file is only read, never modified,  │ │
│  moved or copied.                            │   │ │  moved or copied.                        │ │
│                                              │   │ ╰ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ╯ │
└──────────────────────────────────────────────┘   └──────────────────────────────────────────────┘
                    1. Idle                                     2. Drag targeted

┌──────────────────────────────────────────────┐   ┌──────────────────────────────────────────────┐
│                                              │   │                                              │
│      Inspect a local audio file's            │   │      Inspect a local audio file's            │
│      technical properties.                   │   │      technical properties.                   │
│                                              │   │                                              │
│      [ Choose audio file… ]  (disabled)      │   │        [ Choose another file… ]              │
│      Or drag one onto this window.           │   │      Or drag one onto this window.           │
│  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐    │   │  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐    │
│  │        ◐   Inspecting…              │    │   │  │ ⚠  That file could not be opened     │    │
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘    │   │  │    for inspection.                   │    │
│                                              │   │  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘    │
│  The file is only read, never modified,      │   │  The file is only read, never modified,      │
│  moved or copied.                            │   │  moved or copied.                            │
└──────────────────────────────────────────────┘   └──────────────────────────────────────────────┘
                   3. Working                                     4. Failed
```

**Advantage** — the constant part is constant: the purpose, the action and the trust line hold their
position through every transition, so the state region is the only thing a person has to look at.
**Cost** — the region occupies space in idle whether or not it is reserved; if it is not reserved, the
trust line moves by one line's height on transition, which is the one compromise this option makes.
**macOS** — idiomatic; the shape of a sheet or a settings pane's status area. **Cognitive load** — low,
and lower than A across transitions. **Scalability** — good: a further state is another occupant of one
region, at one place, with one set of accessibility rules.

### Option C — from scratch: the window as an explicit drop zone

```
┌──────────────────────────────────────────────┐   ┌──────────────────────────────────────────────┐
│ ╭ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ╮ │   │ ╭══════════════════════════════════════════╮ │
│ │                                          │ │   │ ║                                          ║ │
│ │   Drop an audio file here                │ │   │ ║        Drop one audio file               ║ │
│ │                                          │ │   │ ║                                          ║ │
│ │           or                              │ │   │ ║                                          ║ │
│ │      [ Choose audio file… ]              │ │   │ ║      [ Choose audio file… ]              ║ │
│ │                                          │ │   │ ║                                          ║ │
│ │  The file is only read, never modified,  │ │   │ ║  The file is only read, never modified,  ║ │
│ │  moved or copied.                        │ │   │ ║  moved or copied.                        ║ │
│ ╰ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ╯ │   │ ╰══════════════════════════════════════════╯ │
└──────────────────────────────────────────────┘   └──────────────────────────────────────────────┘
                    1. Idle                                     2. Drag targeted
```

Working and failed degenerate to B's — the zone has nothing to say about either — which is itself the
finding: C is B plus a permanent box.

**Advantage** — drop is unmissable. **Cost** — three, and they compound. The box **teaches a smaller
target than the truth**: the real destination is the whole window, in every state, and a person who
learns the box will aim at it while a report is on screen and there is no box. It **duplicates the
overlay**, which already draws a border on targeting, so targeted state must either double the border or
suppress its own. And it **inverts the hierarchy**: drop becomes the headline and the keyboard-reachable
action becomes the fallback, which is backwards for accessibility. **macOS** — weakest of the three; a
persistent dashed rectangle is a web-upload idiom. **Cognitive load** — low but misdirected.
**Scalability** — poor.

### Chosen: **B**

A is safe and keeps a real defect — the surface reflows on exactly the transitions a person is watching.
C buys discoverability by teaching something false about the target. B keeps the whole window as the
destination, states the alternative in words next to the action, and gives the varying content one home.

## 5. The three states

### Idle — four things, in this order

1. **what the app does**, stated for this build and not for the roadmap;
2. **the primary action**, visually the heaviest thing on the surface;
3. **the drag-and-drop alternative**, beside the action rather than inside a paragraph;
4. **the read-only promise**, quiet, last, and always present.

Nothing else. No feature list, no capability cards, no sample file, no second call to action, no tips.

### Working — what the app can honestly say

It can say that an inspection is running. It cannot say **which file** (the state carries none, and one
may not have been chosen yet), **how far** (no quantitative progress exists), or **how long**.

So: the indeterminate indicator stays, one line of status appears beside it, the primary action stays
**present but disabled** rather than disappearing — a control that vanishes reads as a bug and moves
everything below it — and the drop stays refused with the sentence it already has.

**The wording names the operation, not the file or the phase.** The operation began when the person
pressed the button, and choosing the file is part of it. That is also why no `Cancel` appears: the flow
has nothing to cancel, and the one thing a person can dismiss — the panel — is already neutral.

### Failed — the message, and a way out that is named for what it does

The flow's sentence is presented **verbatim**. It is stated in words and given a non-colour marker, so
the failure does not depend on red. Beneath it, the action — which opens the panel, exactly as idle's
does, and is therefore named as choosing a file rather than as retrying one.

The constant part of the shell does not change: a person who failed once still needs to know what the
app does and that their file is not modified.

## 6. Copy — every string, classified

| String | Class | Decision |
| --- | --- | --- |
| `Audio Inspector` (title) | **C** — accidental | Retire from the body. The window title bar already carries it; a heading that repeats the chrome spends the surface's most prominent slot on nothing. |
| `Choose a local audio file — or drag one onto this window — to inspect its technical properties.` | **B** — functional | Split. Both claims survive, each at its own weight. |
| `The file is only read, never modified, moved or copied.` | **A** — contractual / trust | **Verbatim, and made a requirement.** It is the product's only trust statement on this surface. |
| `Choose audio file…` | **B** | Keep. It matches the panel and the house sentence case (`Choose another file…`, `Compare with another file…`). |
| `Try again` | **C** — and wrong | Replace. Nothing is retried; the action opens the panel. |
| `That file could not be opened for inspection.` | **D** — flow-supplied | **Never rewritten here.** Presented as given. |
| `Drop one audio file` | **A** — pinned by the capability | Untouched. |
| `Drop one file at a time.` / `That item cannot be inspected.` / `Wait for the current inspection to finish.` | **A** — pinned by tests | Untouched. |

### Proposed

| Slot | Proposed |
| --- | --- |
| idle purpose | *Inspect a local audio file's technical properties.* |
| idle action | `Choose audio file…` *(unchanged)* |
| idle drop | *Or drag one onto this window.* |
| idle trust | *The file is only read, never modified, moved or copied.* *(verbatim)* |
| working status | *Inspecting…* |
| failed message | *That file could not be opened for inspection.* *(verbatim, from the flow)* |
| failed action | `Choose another file…` |

*Inspecting…* is deliberately objectless: it names the operation and nothing about its subject or its
extent. `Choose another file…` is `WorkspaceCopy`'s existing sentence, reused rather than invented.

**Tone**: sober, technical, declarative. No exclamation, no second person imperative beyond the action
itself, no promise about what will be found.

## 7. Accessibility, for this surface only

- **Focus order** follows reading order: purpose, action, drop hint, trust line, and the status or
  failure region when present.
- **The action is reachable by keyboard alone** and is the window's default action, so Return begins an
  inspection. **Drag and drop is never the only way to do anything.**
- **The running state is announced**, not conveyed by an animation alone.
- **The failure is announced and is stated in words**; red is never the only thing that marks it.
- **Targeting is stated in words** — already true, and unchanged.
- The full traversal audit, including VoiceOver rotor behaviour across the whole app, is **R9's**.

## 8. Responsive, conceptually

- **The text takes a reading measure** rather than the window's width, so a wide window does not produce
  one very long line. The block stays centred horizontally.
- **Vertically centred**, not pinned to the top: the surface is a statement, not a form.
- **At the minimum window (720 × 480, unchanged)** everything fits without scrolling or truncation.
- **A larger window adds space around the block, not size to it.** No element grows to fill.
- Exact spacing, type scale and the measure's value are implementation's, and R9 keeps the final pass.

## 9. Drag and drop — the target stays the window

The whole window is the drop destination today, in every state, and **this slice does not narrow it**.
That is the reason option D is refused: a dashed box containing the action would teach that the box is
the target, which is smaller than the truth, and it would duplicate the overlay that already appears on
targeting.

So: the target is unchanged, the overlay is unchanged, and discoverability is carried by the words next
to the action. Feedback stays feedback — the overlay is `allowsHitTesting(false)` and navigates nowhere.

| Moment | What the surface does |
| --- | --- |
| at rest | the drop alternative is stated beside the action |
| targeted | the existing overlay — border plus *"Drop one audio file"* |
| refused | the existing sentence for that reason; the surface is otherwise unchanged |
| accepted | the shell moves to its working state |
| while working | refused with *"Wait for the current inspection to finish."* |

## 10. What R1 guarantees, and this slice must keep

The section navigation is built inside `reportSurface` and nowhere else, so it does not exist while
there is no report. **There is no `WorkspaceSection` case for the empty state, and this slice adds
none.** When an inspection produces a report that did not fail globally, the shell is replaced by the
workspace and R1's own rule selects Overview — a rule this slice neither calls nor changes.

## 11. Known limitation, named rather than papered over

**`.working` spans choosing and reading**, and nothing distinguishes them, so the status line cannot name
the file or the phase. Fixing that properly means giving the flow a state of its own for selection,
which is a change to `ImportFlowModel`'s lifecycle — outside this slice's production scope
(`restructure-inspection-workspace` §2 assigns R2 the pre-inspection surface, not the flow). It is
recorded here so a later slice can take it deliberately rather than discover it.

## 12. Deferred

- The full accessibility and responsive passes — **R9**.
- Any progress reporting, which would require the read path to publish one — not proposed, and it would
  need its own change.
- Cancellation of a running inspection — would require a flow change and a decision about what a
  half-read file leaves behind.
- History, recents, a library, a sidebar — **out by ADR-0004, ADR-0010 and ADR-0026 §12.**
