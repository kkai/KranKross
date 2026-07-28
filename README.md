# KranKross

A nerd-themed nonogram (Picross) game for the [Playdate](https://play.date), where the crank actually solves the puzzle.

## Controls

| Input | Action |
|---|---|
| D-pad | Move the cursor. Hold to repeat. |
| A | Fill a cell. **Hold + d-pad** to drag a run along a line. |
| B | Mark a cross. **Hold + d-pad** to drag a run of crosses. |
| Crank | Zoom: Overview (8px) / Standard (12px) / Close (20px) |
| A + B | Back to the puzzle list |

A drag locks to the axis of its first movement, so a wobbling thumb can't smear paint across two lines.

The crank is never required — every puzzle is solvable with the d-pad alone, and a docked crank blocks nothing.

## Large grids

Puzzles run up to 20×20. When a board is bigger than the screen the camera follows the cursor with a dead-zone, and the clue gutters **stay pinned to the viewport edges** like frozen spreadsheet headers — losing sight of your clues while panning is the worst failure mode in large-grid picross.

Clue numbers are pre-rendered 1-bit tiles rather than drawn text, one sheet per zoom level. A two-digit clue occupies exactly one slot by construction, so the gutters cannot overlap regardless of font metrics. `build_clue_tiles.py` generates the sheets.

## Puzzles

38 hand-authored puzzles across six packs — Retro Computing, Programming, Hardware, Math and Science, Sci-Fi, Mainframe. No procedural generation; every picture is drawn by hand.

Every puzzle is verified at build time by an iterative line solver. A puzzle only ships if the solver reconstructs it completely using per-line deduction alone, which proves two things at once:

- the clues admit exactly one solution, and
- a player can reach it without ever guessing.

Puzzles that are technically unique but need backtracking are rejected — players experience those as unfair.

## Authoring puzzles

Puzzles are ASCII art in `puzzles/*.txt`, so they diff cleanly and need no binary assets:

```
pack: Retro Computing

puzzle: Floppy Disk
##########
#..####..#
...
```

Build and validate:

```bash
python3 build_puzzles.py     # -> source/puzzles.lua, rejects bad puzzles
python3 build_clue_tiles.py  # -> source/img/clues-*.png  (--preview for mockups)
python3 test_build_puzzles.py
lua test_model.lua           # model cross-check + board layout assertions
```

`lua test_model.lua` asserts, for every puzzle at every zoom level, that no clue
tile overlaps another, intrudes into the grid, or detaches from the rows it
labels. That gate exists because an earlier build shipped with clue numbers
overlapping by 2px and bleeding into the first grid row.

`build_puzzles.py` exits non-zero if any puzzle fails, so it doubles as a pre-commit gate.

## Building

Requires the Playdate SDK (`pdc` on your `PATH`).

```bash
pdc source KranKross.pdx
open KranKross.pdx          # macOS: runs in the Playdate Simulator
```

## Layout

```
puzzles/*.txt          puzzle source (ASCII art)
build_puzzles.py       converter + line-solver validator
build_clue_tiles.py    pre-rendered 1-bit clue number tiles
source/
  main.lua             entry point
  constants.lua        zoom-level table -- all board geometry derives from it
  game.lua             state machine, input, zoom, drag painting
  model/puzzle.lua     flat row-major grid, digit-string decoding
  model/numbers.lua    clue derivation and line-completion tracking
  model/progress.lua   best times via playdate.datastore
  ui/board.lua         pinned clue gutters, scrolling grid, camera, cursor
  puzzles.lua          generated -- do not edit
```

## Credits

By [Kai Kunze](https://geistpro.itch.io).

The data model — a flat row-major grid stored as a digit string, and the single-scan clue derivation — was informed by [Sketch, Share, Solve](https://codeberg.org/monometric/sketch-share-solve) by Rebecca König, MIT licensed. It's a genuinely good piece of work and worth your money. No puzzles, art, or audio from that project are used here.

## License

MIT — see [LICENSE](LICENSE).
