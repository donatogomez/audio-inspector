## ADDED Requirements

### Requirement: Present one continuous surface until a report exists

Before any report is presented, the system SHALL present a **single surface** that states what the
application does, offers **exactly one** primary way to choose a file, and states that a file may be
dragged onto the window instead. The idle, running and failed conditions SHALL be states of that one
surface: the statement of purpose, the primary action and the drag-and-drop alternative SHALL be present
in **every** one of them, and SHALL NOT be replaced by a different surface as the state changes.

The surface SHALL offer no second action equivalent to the primary one, and SHALL NOT present a history,
a list of previously inspected files, a library, sample content, or any action that does not perform
work the system can actually do.

The primary action SHALL be operable without a pointer, and dragging SHALL NOT be the only way to reach
any behaviour this surface offers.

#### Scenario: The application is launched

- **WHEN** the application is launched and no file has been inspected
- **THEN** the surface states what the application does, offers one way to choose a file, and states that
  a file may be dragged onto the window

#### Scenario: The surface is the same surface in every pre-report state

- **WHEN** the surface is idle, is running an inspection, or is reporting that an inspection could not be
  started
- **THEN** the statement of purpose, the primary action and the drag-and-drop alternative are present in
  all three

#### Scenario: The primary action is reachable without a pointer

- **WHEN** the surface is presented and no pointer is used
- **THEN** the action that chooses a file can be reached and invoked from the keyboard, and it carries a
  label that names what it does

### Requirement: State that the source file is only read

The pre-report surface SHALL state, in words and in every one of its states, that the chosen file is
read and is not modified, moved or copied. The statement SHALL be present whether or not a file has been
chosen, and SHALL NOT be conditional on any state, hover, disclosure or scroll position.

This states a guarantee the system already keeps; it SHALL NOT be reworded into a promise about results,
safety, privacy or what an inspection will find.

#### Scenario: The guarantee is stated before anything is chosen

- **WHEN** the surface is idle
- **THEN** it states that the file is only read, and never modified, moved or copied

#### Scenario: The guarantee survives every pre-report state

- **WHEN** an inspection is running, or an inspection could not be started
- **THEN** the same statement is still present

### Requirement: Show that an inspection is running without claiming progress

While an inspection is running, the surface SHALL indicate that work is under way using an
**indeterminate** indicator and a statement in words. It MUST NOT state or imply a quantity the system
does not have: no percentage, no fraction, no completed or remaining count, no step number, no elapsed or
estimated time, and no named phase.

It MUST NOT name the file being inspected, because the running state also covers the moment before a file
has been chosen.

The primary action SHALL remain present and SHALL be unavailable while an inspection is running, rather
than being removed. A drop performed while an inspection is running SHALL be refused with the existing
message and SHALL NOT start a second inspection.

The surface SHALL NOT offer to cancel an inspection unless the system can actually stop one.

#### Scenario: An inspection is running

- **WHEN** an inspection has been started and no result has arrived
- **THEN** the surface states in words that an inspection is under way, shows an indeterminate indicator,
  and states no percentage, count, step or time

#### Scenario: The running state names no file

- **WHEN** an inspection is running
- **THEN** the surface names no file, because a file may not have been chosen yet

#### Scenario: The primary action stays put while an inspection runs

- **WHEN** an inspection is running
- **THEN** the action that chooses a file is still present and is unavailable, rather than removed

#### Scenario: A drop while an inspection is running

- **WHEN** an item is dropped while an inspection is running
- **THEN** the surface states that the current inspection must finish, and no second inspection starts

### Requirement: Keep a way forward when an inspection cannot be started

When a selection cannot be turned into an inspection at all, the surface SHALL present the system's own
message for that failure, unaltered, and SHALL keep a way forward available: choosing another file
through the primary action, or dragging one onto the window.

The failure SHALL be conveyed **in words**, and colour alone SHALL NOT be what distinguishes it from
ordinary text. The failure SHALL NOT be presented as a report, SHALL NOT be attributed to the reader, and
SHALL NOT disclose a path, a URL or a framework error.

An action SHALL NOT be labelled as retrying, repeating or re-running the failed selection, because the
system retains nothing about it; an action that opens the file chooser SHALL be named for choosing a
file.

#### Scenario: An inspection could not be started

- **WHEN** a selection cannot be turned into an inspection
- **THEN** the surface presents the system's message for it, marks it as a failure by more than colour,
  and still offers a way to choose another file

#### Scenario: Recovering after a failure

- **WHEN** a failure is shown and the reader chooses another file that inspects successfully
- **THEN** the report is presented and no trace of the failure remains

#### Scenario: Dragging after a failure

- **WHEN** a failure is shown and one valid local audio file is dropped onto the window
- **THEN** a new inspection starts, exactly as it would from the idle state

#### Scenario: No action claims to retry the failed selection

- **WHEN** a failure is shown
- **THEN** no action on the surface is named as retrying, repeating or re-running the selection that
  failed

### Requirement: The pre-report surface is not part of the report's navigation

The surface presented before a report SHALL NOT be a section of the report workspace, SHALL NOT appear in
the workspace's section navigation, and SHALL NOT be selectable as one. The workspace's section
navigation SHALL NOT be presented while no report exists.

When an inspection produces a report, the pre-report surface SHALL be replaced by the report workspace,
and the section the workspace then presents SHALL be decided by the workspace's own rule and by nothing
this surface does.

#### Scenario: No section navigation before a report

- **WHEN** no report is presented
- **THEN** the workspace's section navigation is not presented, and the pre-report surface is not one of
  its sections

#### Scenario: A report replaces the surface

- **WHEN** an inspection produces a report
- **THEN** the pre-report surface is no longer presented, the report workspace is, and the selected
  section is the one the workspace's own rule chooses

#### Scenario: The section list is unchanged by this surface

- **WHEN** the application is built
- **THEN** the workspace's sections are exactly the five it already defines, and no case exists for an
  empty, idle, working or failed state
