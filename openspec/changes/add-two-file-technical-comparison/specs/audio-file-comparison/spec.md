## ADDED Requirements

### Requirement: Select a second local audio file to compare against an open report

From a report already on screen, the system SHALL offer to compare it against a second local audio
file, chosen through the **same** selection path a first inspection uses. The second file SHALL be
inspected by the **same** pipeline, producing a report of the same kind, with the same states, the same
warnings and the same global status.

Access to each file SHALL remain scoped to its own inspection: the two files are read one after the
other, nothing is retained beyond the resulting reports, and no location is disclosed for either.

The system SHALL NOT require both files to be chosen together, SHALL NOT accept a multiple selection,
and SHALL NOT compare more than two files at a time.

#### Scenario: A second file is chosen from an open report

- **WHEN** the user chooses a second file to compare against the report on screen
- **THEN** the second file is inspected exactly as a first file is, and both files' technical facts are
  presented together with a comparison of them

#### Scenario: The same file is chosen twice

- **WHEN** the user chooses, as the second file, the file the open report already describes
- **THEN** the comparison is produced honestly from the two reports, every comparable property reports
  the same value, and the system claims nothing further about the two selections being one file

### Requirement: Keep each file independently inspectable

Comparing SHALL NOT alter, degrade or reinterpret either file's own inspection. Each report SHALL
remain exactly what an inspection of that file alone produces — the same properties, the same states,
the same warnings, the same status — and SHALL remain readable on its own terms.

The export of a single inspection SHALL be unchanged: no comparison data enters it, and its contract
SHALL NOT gain a second inspected file.

#### Scenario: The first report is unaffected

- **WHEN** a second file is inspected for comparison
- **THEN** the first file's properties, warnings and status are identical to what they were before, and
  its export is byte-identical to the export of the same file inspected alone

### Requirement: Compare technical properties as same, different, or not comparable

For every technical property both reports carry, the system SHALL state exactly one of three outcomes:
the two are the **same**, the two are **different**, or the two are **not comparable**. The set SHALL
be exhaustive, so no property is left without an outcome.

A property SHALL be compared **only when both sides carry an available value**. Any other combination
of states SHALL yield *not comparable*, including when a value was read but is not reliable: comparing
an unreliable reading would present it as a comparable fact.

Comparison SHALL be **exact**. Duration in particular SHALL be compared exactly, with no tolerance,
no rounding and no alignment: what is compared is the declared or observed technical fact, never
whether two files might hold the same recording.

A declared rate and an estimated rate SHALL NEVER be compared against one another. Each SHALL be
compared only against its counterpart of the same kind, because they are not measurements of the same
thing.

#### Scenario: Two available values that agree

- **WHEN** both files report an available value for the same property and the values are equal
- **THEN** that property is reported as the same, carrying the value

#### Scenario: Two available values that disagree

- **WHEN** both files report an available value for the same property and the values are not equal
- **THEN** that property is reported as different, carrying both values as evidence and nothing else

#### Scenario: A duration differing by a small amount

- **WHEN** two files report available durations that differ by any amount, however small
- **THEN** the duration is reported as different, and the system does not treat the two as equivalent
  and does not suggest the files may hold the same recording

#### Scenario: A value that is not reliable

- **WHEN** one file reports a property as read-but-unreliable and the other reports an available value
- **THEN** the property is reported as not comparable, and no equality or difference is asserted

### Requirement: State why a comparison is not available

Where two properties cannot be compared, the system SHALL preserve **which state each side was in** —
available, not carried by the file, not expressible by the format, read but unreliable, or failed to
extract — so that the reason is distinguishable rather than collapsed into a single "missing".

A property SHALL NOT be reported as not comparable when both sides carry an available value; that
combination SHALL be unrepresentable.

Each file's warnings and global status SHALL be presented alongside its own facts, and SHALL NOT
themselves be compared: a warning is contextual evidence about how one report was produced, not a
property with a useful equality.

#### Scenario: A format that cannot express a property

- **WHEN** one file's format cannot express bit depth and the other reports an available bit depth
- **THEN** the property is reported as not comparable, stating that one side's format cannot express it
  rather than that the two differ

#### Scenario: A property whose extraction failed on one side

- **WHEN** extracting a property errored for one file and succeeded for the other
- **THEN** the property is reported as not comparable, and the failure is distinguishable from the
  property simply being absent

#### Scenario: Neither file carries a property

- **WHEN** neither file carries a given property
- **THEN** the property is reported as not comparable, and the system does not report the two as the
  same on the grounds that both are absent

### Requirement: Never order, rank or score a comparison

The system SHALL NOT state or imply that either file is better, worse, preferable, higher quality, more
authentic, more trustworthy, or the one to keep. It SHALL NOT order the two files, SHALL NOT mark
either as a winner, and SHALL NOT present a difference as an improvement or a regression.

The system SHALL NOT produce an aggregate of any kind over the comparison: no similarity percentage, no
score, no grade, and no count of differences presented as a measure of how alike the two files are.

A difference in a property SHALL NOT be presented as a defect. In particular, a higher sample rate,
bitrate or bit depth SHALL NOT be presented as better, and a lossy codec SHALL NOT be presented as
worse.

#### Scenario: Two files differing in sample rate

- **WHEN** two files report different available sample rates
- **THEN** the difference is stated with both values, and neither file is marked as better, preferred,
  or the one to keep

#### Scenario: A comparison with many differences

- **WHEN** the two files differ in most of their properties
- **THEN** no overall measure of similarity or difference is presented, and no verdict is drawn from
  how many properties differ

### Requirement: Draw no conclusion about origin or identity from a comparison

The system SHALL NOT state or imply, from a comparison of technical properties, that the two files hold
the same recording, that one was produced from the other, that either is a transcode, a re-encode, a
fake or authentic, or that either has been altered.

It MAY state what is observable — that two properties are the same, that they differ, that one could
not be compared — and MUST NOT state what that observation implies about either file's origin.

#### Scenario: Two files with matching technical properties

- **WHEN** every comparable property of two files reports the same value
- **THEN** the system states that those properties are the same, and does not state or imply that the
  files hold the same audio, the same recording, or that one derives from the other

### Requirement: Survive a failed or cancelled second inspection without corrupting the first

A second file that cannot be inspected, or whose inspection the user cancels, SHALL NOT alter, discard
or degrade the first file's report.

A cancelled second inspection SHALL leave the first report on screen and SHALL NOT be presented as a
limitation of either file. A second file that fails globally SHALL be presented as a report whose
status is failed, with its properties not comparable, rather than as a failure of the comparison
feature or of the first file.

A result belonging to a superseded second selection SHALL NOT be shown.

#### Scenario: The second inspection is cancelled

- **WHEN** the user cancels the inspection of the second file
- **THEN** the first report remains exactly as it was, no comparison is shown, and nothing states that
  either file lacks anything

#### Scenario: The second file cannot be opened

- **WHEN** the second file cannot be inspected at all
- **THEN** its report is shown with a failed status, every property is reported as not comparable, and
  the first file's report is unchanged

#### Scenario: A third file replaces the second

- **WHEN** the user chooses another file to compare while a second inspection is still running
- **THEN** the superseded result is discarded, the newer one is shown, and the first report is
  unchanged throughout

#### Scenario: The first file's own work is still in flight

- **WHEN** a second file is chosen while work belonging to the first file has not finished
- **THEN** that work continues and its result is still delivered to the first file's own presentation,
  and starting, finishing, failing or cancelling the second inspection neither cancels it nor discards
  its result

### Requirement: Present both files' facts and the comparison in words

The comparison SHALL be presented so that both files' values and the outcome for each property are
readable as text. Colour SHALL NOT be the sole carrier of any meaning: whether two properties are the
same, different or not comparable SHALL be stated in words, never only by a colour, a symbol or a
position.

The presentation SHALL be exposed to an assistive reader such that, for each property, the property, both
files' values and the comparison outcome are announced, with no characterisation of either file's
quality. Where a property is not comparable, the reason SHALL be available as text.

#### Scenario: The comparison is read without seeing it

- **WHEN** the comparison is read with an assistive reader
- **THEN** each property is announced with both files' values and whether they are the same, different
  or not comparable, and no announcement characterises either file as better or worse

#### Scenario: The comparison is read without colour

- **WHEN** the comparison is viewed with colour removed or unavailable
- **THEN** every outcome remains readable, because each is stated in words rather than shown by colour
  alone
