#!/usr/bin/env python3
"""Generate 1-bit clue-number tiles for KranKross.

Clue values are bounded by the grid dimension (max 20), so every possible clue
is pre-rendered as a fixed-size tile rather than drawn with drawText. That is
the whole point: a two-digit clue occupies exactly one slot by construction, so
the gutter layout cannot overlap no matter what the font metrics happen to be.
Text measurement is what broke the previous layout.

Emits Playdate image tables:

    source/img/clues-<level>-table-<W>-<H>.png

Frame N holds the numeral N, for N in 1..20.

    python3 build_clue_tiles.py            # write the sheets
    python3 build_clue_tiles.py --preview  # also render board mockups to check
                                           # legibility at each zoom level
"""

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).parent
IMG_OUT = ROOT / "source" / "img"
PREVIEW_OUT = ROOT / "preview"

MAX_CLUE = 20
SHEET_COLS = 5

# --------------------------------------------------------------------------
# Digit glyphs, hand-drawn so they stay crisp at 1-bit. '1' is ink.
# --------------------------------------------------------------------------

DIGITS_3x5 = {
    "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"],
    "7": ["111", "001", "001", "001", "001"],
    "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"],
}

DIGITS_5x7 = {
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
}

DIGITS_7x11 = {
    "0": [".11111.", "11...11", "11...11", "11...11", "11...11", "11...11",
          "11...11", "11...11", "11...11", "11...11", ".11111."],
    "1": ["...11..", "..111..", ".1111..", "...11..", "...11..", "...11..",
          "...11..", "...11..", "...11..", "...11..", "1111111"],
    "2": [".11111.", "11...11", "11...11", ".....11", "....11.", "...11..",
          "..11...", ".11....", "11.....", "11.....", "1111111"],
    "3": [".11111.", "11...11", ".....11", ".....11", "..1111.", ".....11",
          ".....11", ".....11", "11...11", "11...11", ".11111."],
    "4": ["....11.", "...111.", "..1111.", ".11.11.", "11..11.", "11..11.",
          "1111111", "....11.", "....11.", "....11.", "....11."],
    "5": ["1111111", "11.....", "11.....", "11.....", "111111.", ".....11",
          ".....11", ".....11", "11...11", "11...11", ".11111."],
    "6": ["..1111.", ".11....", "11.....", "11.....", "111111.", "11...11",
          "11...11", "11...11", "11...11", "11...11", ".11111."],
    "7": ["1111111", ".....11", ".....11", "....11.", "....11.", "...11..",
          "...11..", "..11...", "..11...", ".11....", ".11...."],
    "8": [".11111.", "11...11", "11...11", "11...11", ".11111.", "11...11",
          "11...11", "11...11", "11...11", "11...11", ".11111."],
    "9": [".11111.", "11...11", "11...11", "11...11", "11...11", ".111111",
          ".....11", ".....11", "....11.", "..111..", ".111..."],
}

# level -> (cell size, tile w, tile h, glyph set, glyph w, glyph h, gap)
# Tile width is always the cell size so a top-gutter tile centres exactly over
# its column. Tile height is the vertical pitch of the top gutter.
LEVELS = {
    "overview": dict(cell=8,  tile=(8, 6),   glyphs=DIGITS_3x5,  gw=3, gh=5,  gap=1),
    "standard": dict(cell=12, tile=(12, 10), glyphs=DIGITS_5x7,  gw=5, gh=7,  gap=1),
    "close":    dict(cell=20, tile=(20, 14), glyphs=DIGITS_7x11, gw=7, gh=11, gap=2),
}

INK = (0, 0, 0, 255)
CLEAR = (0, 0, 0, 0)


def draw_glyph(img, glyph, ox, oy):
    for dy, row in enumerate(glyph):
        for dx, ch in enumerate(row):
            if ch == "1":
                img.putpixel((ox + dx, oy + dy), INK)


def render_tile(value, spec):
    tw, th = spec["tile"]
    tile = Image.new("RGBA", (tw, th), CLEAR)

    text = str(value)
    gw, gh, gap = spec["gw"], spec["gh"], spec["gap"]
    total_w = len(text) * gw + (len(text) - 1) * gap
    if total_w > tw:
        raise ValueError(f"clue {value} needs {total_w}px in a {tw}px tile")

    ox = (tw - total_w) // 2
    oy = (th - gh) // 2
    for ch in text:
        draw_glyph(tile, spec["glyphs"][ch], ox, oy)
        ox += gw + gap
    return tile


def build_sheet(level, spec):
    tw, th = spec["tile"]
    rows = (MAX_CLUE + SHEET_COLS - 1) // SHEET_COLS
    sheet = Image.new("RGBA", (SHEET_COLS * tw, rows * th), CLEAR)

    for value in range(1, MAX_CLUE + 1):
        idx = value - 1
        col, row = idx % SHEET_COLS, idx // SHEET_COLS
        sheet.paste(render_tile(value, spec), (col * tw, row * th))

    IMG_OUT.mkdir(parents=True, exist_ok=True)
    path = IMG_OUT / f"clues-{level}-table-{tw}-{th}.png"
    sheet.save(path)
    return path


# --------------------------------------------------------------------------
# Preview: render a real board so legibility can be judged before writing Lua
# --------------------------------------------------------------------------

def preview_board(level, spec, width, height, scale=3):
    """Mock up the worst case: every line carrying the maximum clue count."""
    cell = spec["cell"]
    tw, th = spec["tile"]
    slots_l = (width + 1) // 2      # provable max clues in a row
    slots_t = (height + 1) // 2

    left_gutter = slots_l * tw
    top_gutter = slots_t * th
    total_w = left_gutter + width * cell
    total_h = top_gutter + height * cell

    img = Image.new("RGBA", (400, 240), (255, 255, 255, 255))
    ox = max(0, (400 - total_w) // 2) + left_gutter
    oy = max(0, (240 - total_h) // 2) + top_gutter

    # Grid lines.
    for gx in range(width + 1):
        for y in range(oy, min(240, oy + height * cell + 1)):
            x = ox + gx * cell
            if 0 <= x < 400:
                img.putpixel((x, y), (0, 0, 0, 255) if gx % 5 == 0 else (150, 150, 150, 255))
    for gy in range(height + 1):
        for x in range(ox, min(400, ox + width * cell + 1)):
            y = oy + gy * cell
            if 0 <= y < 240:
                img.putpixel((x, y), (0, 0, 0, 255) if gy % 5 == 0 else (150, 150, 150, 255))

    # Worst-case clue fill: alternating 1s and 2-digit values.
    for row in range(height):
        for s in range(slots_l):
            value = 20 - (s % 3) * 7 if (row + s) % 2 == 0 else (s % 9) + 1
            tile = render_tile(max(1, min(MAX_CLUE, value)), spec)
            x = ox - (slots_l - s) * tw
            y = oy + row * cell + (cell - th) // 2
            if x >= 0 and y >= 0:
                img.alpha_composite(tile, (x, y))
    for col in range(width):
        for s in range(slots_t):
            value = 20 - (s % 3) * 7 if (col + s) % 2 == 0 else (s % 9) + 1
            tile = render_tile(max(1, min(MAX_CLUE, value)), spec)
            x = ox + col * cell + (cell - tw) // 2
            y = oy - (slots_t - s) * th
            if x >= 0 and y >= 0:
                img.alpha_composite(tile, (x, y))

    PREVIEW_OUT.mkdir(parents=True, exist_ok=True)
    out = PREVIEW_OUT / f"board-{level}-{width}x{height}.png"
    img.resize((400 * scale, 240 * scale), Image.NEAREST).save(out)
    fits = "FITS" if total_w <= 400 and total_h <= 240 else "SCROLLS"
    print(f"  {level:9s} {width:2d}x{height:<2d} gutters L={left_gutter:3d} T={top_gutter:3d}"
          f"  total {total_w:3d}x{total_h:3d}  {fits}  -> {out.name}")
    return total_w, total_h


def main():
    print("clue tile sheets")
    for level, spec in LEVELS.items():
        path = build_sheet(level, spec)
        tw, th = spec["tile"]
        two_digit = 2 * spec["gw"] + spec["gap"]
        print(f"  {level:9s} tile {tw}x{th}  widest clue {two_digit}px  -> {path.name}")

    if "--preview" in sys.argv:
        print("\nboard mockups (worst-case clue density)")
        for level, spec in LEVELS.items():
            for w, h in [(10, 10), (15, 10), (15, 15), (20, 20)]:
                preview_board(level, spec, w, h)

    return 0


if __name__ == "__main__":
    sys.exit(main())
