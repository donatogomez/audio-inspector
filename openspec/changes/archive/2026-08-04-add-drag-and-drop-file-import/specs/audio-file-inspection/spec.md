## MODIFIED Requirements

### Requirement: Select a single local audio file

The system SHALL let the user choose one local audio file through an **explicit user selection** —
either the native macOS file-open panel **or by dragging the file onto the app window** — under App
Sandbox, gaining user-granted access to that file for the duration of the inspection. **Exactly one
local file SHALL be accepted per operation**, and **both mechanisms SHALL converge on the same
inspection path and produce the same report for the same file**. The system MUST NOT modify the file.
It MUST NOT require any entitlement beyond App Sandbox plus the user-selected file access those
mechanisms imply — `com.apple.security.files.user-selected.read-write`, which one executable setting
applies to both the inspected file and the export destination (ADR-0013) — and MUST NOT use any
folder-wide or system-wide entitlement. Access SHALL be held only for the operation that needs it, and
the system MUST NOT persist any URL or create any security-scoped bookmark. The source file is treated
as read-only by the system's own APIs; the only file the system writes is the export destination the
user picks. A selection that cannot be turned into a single inspectable local file SHALL be rejected
without starting an inspection, without discarding any result already presented, and without disclosing
any path or URL.

#### Scenario: User picks a file in the open panel

- **WHEN** the user selects a supported local audio file in the open panel
- **THEN** the system obtains read access to that file for the inspection and begins reading its
  basic properties, without modifying the file

#### Scenario: User cancels selection

- **WHEN** the user dismisses the open panel without choosing a file
- **THEN** no inspection starts and the app remains in its prior state

#### Scenario: User drops a single audio file from the initial state

- **WHEN** no report is displayed and the user drops one local audio file onto the app window
- **THEN** the system obtains read access to that file, inspects it, and presents the resulting report,
  without modifying the file and without persisting its location

#### Scenario: User drops a single audio file while a report is displayed

- **WHEN** a report is displayed and the user drops one valid local audio file onto the app window
- **THEN** a new inspection starts and, on completion, the new report is presented

#### Scenario: User drops more than one item

- **WHEN** the user drops two or more items at once
- **THEN** the system rejects the whole drop, selects none of the items, starts no inspection, and
  states that a single audio file is expected

#### Scenario: User drops something that is not a single local file

- **WHEN** the dropped item is not a local file, or is a folder rather than a file
- **THEN** the system rejects it, starts no inspection, and shows a neutral, recoverable message that
  discloses no path or URL

#### Scenario: A rejected drop preserves the previous result

- **WHEN** a drop is rejected while a report is displayed
- **THEN** that report remains displayed, the rejection is not reported as an inspection failure, and
  the next accepted selection clears the rejection message

#### Scenario: User drops while an inspection is running

- **WHEN** an inspection is already in flight and another item is dropped
- **THEN** the drop does not start a second inspection, the running inspection is unaffected, and at
  most one inspection exists at any time

#### Scenario: Both mechanisms use the same inspection path

- **WHEN** the same file is inspected once through the open panel and once by dropping it
- **THEN** both produce the same report content and the same exported JSON, apart from the envelope
  fields the exporter generates per export

#### Scenario: Targeting feedback states what is expected

- **WHEN** a drag operation is over the app window and the dragged items are not yet delivered
- **THEN** the window indicates that it is the target of the operation and states that one audio file is
  expected, without asserting that the dragged content is valid

#### Scenario: Feature modules never receive a file location

- **WHEN** the source of the feature modules is inspected
- **THEN** no feature module uses the `URL` type or imports AppKit, and the selection mechanism reaches
  them only as an opaque action and safe visual state

#### Scenario: No new entitlement or bookmark is introduced

- **WHEN** a file is selected by either mechanism and inspected
- **THEN** the app declares only App Sandbox and `com.apple.security.files.user-selected.read-write`,
  creates no security-scoped bookmark, and retains no URL after the inspection completes
