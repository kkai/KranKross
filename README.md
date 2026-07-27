# KranKross

A nerd-themed nonogram (Picross) game for the [Playdate](https://play.date), where the crank actually solves the puzzle.

## The crank

Most Playdate nonogram games treat the crank as a menu scroller. KranKross puts it in the solving loop:

- **D-pad** moves the cursor, **A** fills a cell, **B** marks a cross — the conventional scheme, fully sufficient on its own.
- **Hold A (or B) and crank** to extend the mark into a run along the axis you last moved. Release to commit.

That mirrors how nonograms are actually solved: you deduce "this row has a run of four", then draw four. The crank maps to run length — a continuous quantity, which is exactly what a rotary input is good at. Roughly 45° per cell, so a short flick can't overshoot.

The crank is never on the critical path. Every puzzle is fully solvable with the d-pad alone.

## Puzzles

33 hand-authored puzzles across five packs — Retro Computing, Programming, Hardware, Math and Science, Sci-Fi. No procedural generation; every picture is drawn by hand.

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
python3 test_build_puzzles.py
lua test_model.lua           # cross-checks the Lua model against the Python validator
```

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
source/
  main.lua             entry point
  constants.lua        cell size, gutter metrics, crank sensitivity
  game.lua             state machine, input, run painting
  model/puzzle.lua     flat row-major grid, digit-string decoding
  model/numbers.lua    clue derivation and line-completion tracking
  model/progress.lua   best times via playdate.datastore
  ui/board.lua         clue gutters, grid, cell states, cursor
  puzzles.lua          generated -- do not edit
```

## Credits

By [Kai Kunze](https://geistpro.itch.io).

The data model — a flat row-major grid stored as a digit string, and the single-scan clue derivation — was informed by [Sketch, Share, Solve](https://codeberg.org/monometric/sketch-share-solve) by Rebecca König, MIT licensed. It's a genuinely good piece of work and worth your money. No puzzles, art, or audio from that project are used here.

## License

MIT — see [LICENSE](LICENSE).
