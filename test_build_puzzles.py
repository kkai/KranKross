#!/usr/bin/env python3
"""Tests for the puzzle validator.

Run: python3 test_build_puzzles.py

These matter more than they look. Every bug here is invisible from the game
UI -- it shows up as a player solving a puzzle correctly and being told they
are wrong.
"""

import sys

from build_puzzles import (
    EMPTY,
    FILLED,
    UNKNOWN,
    arrangements,
    derive_clues,
    line_solve,
    parse_pack,
    runs,
    validate,
)

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  ok    {name}")
    else:
        print(f"  FAIL  {name}  {detail}")
        failures.append(name)


def make(rows):
    return {
        "title": "test",
        "width": len(rows[0]),
        "height": len(rows),
        "rows": rows,
    }


print("runs()")
check("empty line", runs([EMPTY] * 5) == ())
check("full line", runs([FILLED] * 5) == (5,))
check("split runs", runs([FILLED, EMPTY, FILLED, FILLED, EMPTY]) == (1, 2))
check("trailing run closes", runs([EMPTY, FILLED, FILLED]) == (2,))

print("\narrangements()")
check("no clues -> one empty arrangement", arrangements((), 3) == ((EMPTY,) * 3,))
check("single clue count", len(arrangements((1,), 3)) == 3)
check("exact fit is unique", len(arrangements((3,), 3)) == 1)
check("two clues need a gap", len(arrangements((1, 1), 3)) == 1)
check(
    "gap is respected",
    arrangements((1, 1), 3)[0] == (FILLED, EMPTY, FILLED),
    arrangements((1, 1), 3)[0],
)
check("overlong clue -> none", arrangements((4,), 3) == ())

print("\nderive_clues() round-trip")
# A plus sign.
grid_rows = [
    ".#.",
    "###",
    ".#.",
]
grid = [FILLED if c == "#" else EMPTY for r in grid_rows for c in r]
row_clues, col_clues = derive_clues(grid, 3, 3)
check("row clues", row_clues == [(1,), (3,), (1,)], row_clues)
check("col clues", col_clues == [(1,), (3,), (1,)], col_clues)

print("\nline_solve()")
solution, solved = line_solve(row_clues, col_clues, 3, 3)
check("plus sign solves", solved)
check("plus sign reconstructs exactly", solution == grid)

# The classic ambiguity: a 2x2 diagonal. Clues (1),(1) / (1),(1) are
# satisfied by both diagonals, so deduction must stall rather than pick one.
amb_rows = ["#.", ".#"]
amb = [FILLED if c == "#" else EMPTY for r in amb_rows for c in r]
amb_row_clues, amb_col_clues = derive_clues(amb, 2, 2)
amb_solution, amb_solved = line_solve(amb_row_clues, amb_col_clues, 2, 2)
check("ambiguous diagonal does NOT solve", not amb_solved)
check("ambiguous diagonal leaves cells unknown", UNKNOWN in amb_solution)

# Contradictory clues must be reported, not crash. Here the rows demand two
# filled cells while both columns are declared empty.
bad_solution, bad_solved = line_solve([(2,), ()], [(), ()], 2, 2)
check("contradictory clues rejected", bad_solution is None and not bad_solved)

print("\nvalidate()")
ok, msgs = validate(make(grid_rows))
check("plus sign accepted", ok, msgs)

ok, msgs = validate(make(amb_rows))
check("ambiguous diagonal rejected", not ok, msgs)
check(
    "rejection explains why",
    any("guessing" in m or "ambiguous" in m for m in msgs),
    msgs,
)

ok, msgs = validate(make(["..", ".."]))
check("empty puzzle rejected", not ok, msgs)

# Dense but legitimate: a solid block is uniquely determined.
ok, msgs = validate(make(["###", "###", "###"]))
check("solid block accepted", ok, msgs)
check("solid block warns about density", any("dense" in m for m in msgs), msgs)

print("\nparse_pack()")
import tempfile
from pathlib import Path

with tempfile.TemporaryDirectory() as td:
    p = Path(td) / "sample.txt"
    p.write_text(
        "pack: Test Pack\n"
        "\n"
        "puzzle: Plus\n"
        ".#.\n"
        "###\n"
        ".#.\n"
        "\n"
        "puzzle: Bar\n"
        "###\n"
    )
    name, puzzles = parse_pack(p)
    check("pack name read", name == "Test Pack", name)
    check("two puzzles parsed", len(puzzles) == 2, len(puzzles))
    check("titles read", [q["title"] for q in puzzles] == ["Plus", "Bar"])
    check("dimensions read", (puzzles[0]["width"], puzzles[0]["height"]) == (3, 3))

    ragged = Path(td) / "ragged.txt"
    ragged.write_text("puzzle: Ragged\n##\n###\n")
    try:
        parse_pack(ragged)
        check("ragged rows rejected", False)
    except Exception as e:
        check("ragged rows rejected", "ragged" in str(e), str(e))

print()
if failures:
    print(f"{len(failures)} test(s) failed: {', '.join(failures)}")
    sys.exit(1)
print("all tests passed")
