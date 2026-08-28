## ADDED Requirements

### Requirement: Lay each lane's words clear of every drawing

A lane's words SHALL be laid out **outside** the area any drawing occupies, and SHALL NOT be drawn over
a drawing, over another lane's words, or over the axis statement. Those words are which file the lane
is, what became of its drawing, and what the part of an axis it does not reach means.

A lane's words SHALL be positioned by the surface's own layout rather than by a fixed measurement chosen
for one drawing: no region reserved for a drawing SHALL be relied upon to also hold text, and no lane's
text SHALL depend for its position on a height that was chosen for a picture.

Each lane SHALL render its words from the presentation that produced them for that lane, so that one
sentence has one owner and cannot be laid out twice in two places.

#### Scenario: A lane whose drawing is accompanied by a sentence

- **WHEN** a lane presents a drawing together with the sentence describing it
- **THEN** the sentence is laid out beneath the drawing's area, and neither the sentence nor the drawing
  is displaced onto the other

#### Scenario: A lane with an out-of-range statement

- **WHEN** a lane's file does not reach the whole of a shared axis
- **THEN** the statement saying so is laid out clear of that lane's drawing and clear of the other lane's
  words

#### Scenario: The words survive a larger text size

- **WHEN** the reader's text size is increased
- **THEN** each lane's words take the space they need and no drawing's area is relied upon to contain
  them
