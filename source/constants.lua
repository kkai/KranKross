-- Screen is 400x240, 1-bit.

SCREEN_W = 400
SCREEN_H = 240

-- Reserved band at the top for pack name and timer. The board never draws here.
HUD_H = 16

-- Cell states. FILLED is deliberately 1 so it compares directly against the
-- solution digits decoded from the puzzle string.
EMPTY = 0
FILLED = 1
CROSSED = 2

-- Zoom levels. Every piece of board geometry derives from this table -- there
-- are deliberately no other pixel constants in the renderer. The previous
-- layout hardcoded clue spacing that did not match the font it drew with, and
-- the numbers overlapped; clue tiles are pre-rendered at exactly these sizes
-- by build_clue_tiles.py so the two can no longer drift apart.
--
-- clue_w is always equal to cell so a top-gutter tile centres over its column.
ZOOM_OVERVIEW = 1
ZOOM_STANDARD = 2
ZOOM_CLOSE = 3

ZOOM_LEVELS = {
	{ name = "overview", cell = 8,  clue_w = 8,  clue_h = 6,  sheet = "img/clues-overview" },
	{ name = "standard", cell = 12, clue_w = 12, clue_h = 10, sheet = "img/clues-standard" },
	{ name = "close",    cell = 20, clue_w = 20, clue_h = 14, sheet = "img/clues-close" },
}

MAX_CLUE_TILE = 20

-- Crank travel needed to step one zoom level.
DEGREES_PER_ZOOM = 100

-- Cursor may roam the middle 60% of the viewport before the camera scrolls.
DEAD_ZONE = 0.6

STATE_SELECT = 1
STATE_PLAYING = 2
STATE_SOLVED = 3

AXIS_H = 1
AXIS_V = 2

SAVE_KEY = "krankross"
