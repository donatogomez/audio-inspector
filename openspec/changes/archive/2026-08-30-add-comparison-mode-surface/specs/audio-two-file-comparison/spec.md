## ADDED Requirements

### Requirement: Read each comparison where its subject is presented

The system SHALL present the comparison of two files' technical properties where it presents those
properties, the comparison of their measurements where it presents those measurements, and their paired
drawings where it presents drawings. It SHALL NOT gather them into a surface of their own.

Each comparison SHALL be the one the domain already produced. The system SHALL NOT re-decide an outcome,
re-derive a difference, apply a threshold or a tolerance, or compare two values a comparison reported as
not comparable.

#### Scenario: Each comparison is read beside its own subject

- **WHEN** a comparison is ready
- **THEN** the property comparison, the measurement comparison and the paired drawings are each presented
  where that kind of content is presented
- **AND** no surface presents all of them together as a comparison of its own

#### Scenario: An outcome is the domain's, rendered

- **WHEN** a compared value is presented
- **THEN** its outcome is the one the comparison produced, and nothing on the surface recomputes,
  overrides or qualifies it

### Requirement: Publish a difference only where the domain publishes one

A surface SHALL present a difference between two values only for a measurement whose comparison carries
one. It MUST NOT compute, display or imply a difference, a ratio, a delta or a change for any other
measurement or property, and MUST NOT give a row a place for one it cannot have.

#### Scenario: Only the measurement that carries a difference shows one

- **WHEN** the measurements of two files are presented
- **THEN** a difference appears only where the comparison published one, and every other row shows both
  values and its outcome without one

#### Scenario: No difference is invented for an amplitude

- **WHEN** two files' true peak or signal levels are presented
- **THEN** both values and the outcome appear, and no difference, ratio or delta between them is shown
