-- Screen is 400x240, 1-bit.

CELL = 16

-- Clue gutters are sized from the widest clue list in the puzzle, not from
-- the theoretical worst case (ceil(n/2)), which would waste most of the screen.
-- Wide enough for a two-digit clue; runs reach 15 on the wider puzzles.
CLUE_W = 12
CLUE_H = 12

-- Cell states. FILLED is deliberately 1 so it compares directly against the
-- solution digits decoded from the puzzle string.
EMPTY = 0
FILLED = 1
CROSSED = 2

-- Crank travel needed to extend a painted run by one cell. Generous on
-- purpose: a short flick must not overshoot a 3-run.
DEGREES_PER_CELL = 45

STATE_SELECT = 1
STATE_PLAYING = 2
STATE_SOLVED = 3

AXIS_H = 1
AXIS_V = 2

SAVE_KEY = "krankross"
