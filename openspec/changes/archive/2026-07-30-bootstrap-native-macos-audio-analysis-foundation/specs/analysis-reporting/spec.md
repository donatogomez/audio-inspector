## ADDED Requirements

### Requirement: Provide a two-level report

The system SHALL present every analysis in two coordinated levels: a plain-language summary and a
technical view. The plain summary SHALL state what was found, whether it warrants review, what
seems reliable, what seems suspicious, and **what cannot be known**. The technical view SHALL
include metrics, methodology, thresholds, confidence, observations, raw data, and the analysis
engine version.

#### Scenario: Both levels available for an analysis

- **WHEN** an analysis completes for an imported file
- **THEN** the user can view a plain-language summary and a technical view of the same result, and
  the technical view shows the engine version

#### Scenario: Summary states the limits of knowledge

- **WHEN** the analysis produces results with residual uncertainty
- **THEN** the plain summary explicitly communicates what cannot be determined from the file, rather
  than implying certainty

### Requirement: Warnings carry a confidence level and avoid overclaiming

Every warning or observation the system emits SHALL carry one of the defined confidence levels
(`none`, `weak`, `medium`, `strong`, `inconclusive`) and SHALL, where applicable, include at least
one alternative explanation. The system MUST NOT present an inference or conclusion as if it were a
raw measured fact, and MUST NOT emit an arbitrary aggregate numeric quality score.

#### Scenario: A cautious warning is emitted

- **WHEN** the analysis detects a persistent spectral cutoff consistent with prior lossy
  compression
- **THEN** the system emits a warning labelled with a confidence level and at least one alternative
  explanation, and does not state a definitive verdict such as "fake MP3"

#### Scenario: No aggregate score

- **WHEN** any report is generated
- **THEN** the output contains no single aggregate 0–100 "quality score"; it presents discrete facts,
  observations, and confidence levels instead

### Requirement: Export the analysis as versioned JSON

The system SHALL export the analysis result as JSON following the versioned contract in
`docs/json-schema-v1.md`, starting at `schemaVersion` = 1. The document SHALL include at least the
top-level fields `schemaVersion`, `analysisEngineVersion`, `generatedAt`, `fileIdentity`,
`mediaProperties`, `measurements`, `findings`, and `analysisStatus`. Each entry in `findings` SHALL
carry a stable `identifier`, `severity`, `confidence`, `evidence`, `explanation`, and
`alternativeExplanations`. Schema changes SHALL be additive where possible; an incompatible change
SHALL increment `schemaVersion`.

#### Scenario: Export produces versioned JSON

- **WHEN** the user exports a completed analysis
- **THEN** the system writes a JSON document with `schemaVersion` = 1, the analysis engine version,
  and the required top-level fields, where each finding includes its confidence, evidence,
  explanation, and any alternative explanations

#### Scenario: Additive schema evolution

- **WHEN** a later engine version adds a new optional field to the export
- **THEN** `schemaVersion` remains 1 (additive change), and only an incompatible change would
  increment it
