#!/usr/bin/env python3
"""Build and validate KranKross puzzle packs.

Reads ASCII-art puzzle definitions from puzzles/*.txt and emits
source/puzzles.lua as a Lua table.

Every puzzle is validated with an iterative line solver. A puzzle is only
accepted if the solver reconstructs it completely using per-line deduction
alone. That proves two things at once:

  * the clues admit exactly one solution (no ambiguity), and
  * a human can reach that solution without ever guessing.

A puzzle that is technically unique but needs backtracking will stall the
solver and be rejected -- players experience those as unfair.

Input format (see puzzles/*.txt):

    pack: Retro Computing

    puzzle: Floppy Disk
    ..########..
    .#........#.
    ############

    puzzle: Cassette
    ...

'#' is a filled cell, '.' is empty. A blank line ends a puzzle.
"""

import json
import sys
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).parent
PUZZLE_DIR = ROOT / "puzzles"
LUA_OUT = ROOT / "source" / "puzzles.lua"

UNKNOWN = -1
EMPTY = 0
FILLED = 1


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------

class ParseError(Exception):
    pass


def parse_pack(path):
    """Parse one .txt pack file into (pack_name, [puzzle, ...])."""
    pack_name = path.stem
    puzzles = []
    title = None
    rows = []

    def flush():
        nonlocal title, rows
        if title is None:
            if rows:
                raise ParseError(f"{path.name}: grid rows before any 'puzzle:' header")
            return
        if not rows:
            raise ParseError(f"{path.name}: puzzle '{title}' has no grid")
        widths = {len(r) for r in rows}
        if len(widths) != 1:
            raise ParseError(
                f"{path.name}: puzzle '{title}' has ragged rows (widths {sorted(widths)})"
            )
        puzzles.append({
            "title": title,
            "width": len(rows[0]),
            "height": len(rows),
            "rows": rows[:],
        })
        title = None
        rows = []

    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.rstrip()
        if line.startswith("#!") or line.startswith("//"):
            continue
        if not line.strip():
            flush()
            continue
        if line.startswith("pack:"):
            pack_name = line[len("pack:"):].strip()
            continue
        if line.startswith("puzzle:"):
            flush()
            title = line[len("puzzle:"):].strip()
            continue
        stripped = line.strip()
        bad = set(stripped) - {"#", "."}
        if bad:
            raise ParseError(
                f"{path.name}:{lineno}: grid row contains {sorted(bad)}; "
                "only '#' and '.' allowed"
            )
        rows.append(stripped)

    flush()
    return pack_name, puzzles


# --------------------------------------------------------------------------
# Clue derivation
# --------------------------------------------------------------------------

def runs(line):
    """Run-length encode the filled cells of a line -> tuple of run lengths."""
    out = []
    count = 0
    for cell in line:
        if cell == FILLED:
            count += 1
        elif count:
            out.append(count)
            count = 0
    if count:
        out.append(count)
    return tuple(out)


def derive_clues(grid, width, height):
    rows = [runs(grid[y * width:(y + 1) * width]) for y in range(height)]
    cols = [runs([grid[y * width + x] for y in range(height)]) for x in range(width)]
    return rows, cols


# --------------------------------------------------------------------------
# Line solver
# --------------------------------------------------------------------------

@lru_cache(maxsize=None)
def arrangements(clues, length):
    """Every 0/1 tuple of `length` cells matching `clues`.

    Cached across the whole run -- the same (clues, length) pair recurs
    constantly, and without this the 15-wide lines get expensive.
    """
    if not clues:
        return (tuple([EMPTY] * length),)

    first, rest = clues[0], clues[1:]
    # Space needed by the remaining clues, plus one gap before each.
    tail = sum(rest) + len(rest)
    out = []
    for start in range(length - tail - first + 1):
        head = [EMPTY] * start + [FILLED] * first
        if rest:
            head.append(EMPTY)
            for sub in arrangements(rest, length - len(head)):
                out.append(tuple(head) + sub)
        else:
            out.append(tuple(head + [EMPTY] * (length - len(head))))
    return tuple(out)


def constrain(known, clues):
    """Narrow a partially-known line.

    Returns the deduced line, or None if the clues contradict what's known.
    Cells that hold the same value across every remaining legal arrangement
    are forced; the rest stay UNKNOWN.
    """
    candidates = [
        arr for arr in arrangements(clues, len(known))
        if all(k == UNKNOWN or k == a for k, a in zip(known, arr))
    ]
    if not candidates:
        return None

    result = []
    for i in range(len(known)):
        first = candidates[0][i]
        result.append(first if all(c[i] == first for c in candidates) else UNKNOWN)
    return result


def line_solve(row_clues, col_clues, width, height):
    """Solve by per-line deduction only.

    Returns (grid, solved). `solved` is False if the solver stalled with
    cells still unknown, or None-grid if the clues are contradictory.
    """
    grid = [UNKNOWN] * (width * height)

    progress = True
    while progress:
        progress = False

        for y in range(height):
            base = y * width
            known = grid[base:base + width]
            deduced = constrain(known, row_clues[y])
            if deduced is None:
                return None, False
            for x in range(width):
                if deduced[x] != known[x]:
                    grid[base + x] = deduced[x]
                    progress = True

        for x in range(width):
            known = [grid[y * width + x] for y in range(height)]
            deduced = constrain(known, col_clues[x])
            if deduced is None:
                return None, False
            for y in range(height):
                if deduced[y] != known[y]:
                    grid[y * width + x] = deduced[y]
                    progress = True

    return grid, UNKNOWN not in grid


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------

def validate(puzzle):
    """Return (ok, [messages]). Messages prefixed FAIL are fatal."""
    width, height = puzzle["width"], puzzle["height"]
    grid = [FILLED if c == "#" else EMPTY for row in puzzle["rows"] for c in row]
    messages = []

    filled = sum(grid)
    if filled == 0:
        return False, ["FAIL: puzzle is entirely empty"]

    density = filled / len(grid)
    if density < 0.30:
        messages.append(f"warn: sparse ({density:.0%} filled) -- may look thin")
    elif density > 0.80:
        messages.append(f"warn: dense ({density:.0%} filled) -- may be trivial")

    row_clues, col_clues = derive_clues(grid, width, height)

    # Round-trip check: clues derived from the solved grid must match.
    solution, solved = line_solve(row_clues, col_clues, width, height)
    if solution is None:
        return False, messages + ["FAIL: clues are contradictory (validator bug)"]

    if not solved:
        unknown = solution.count(UNKNOWN)
        return False, messages + [
            f"FAIL: not solvable by deduction -- {unknown} cell(s) need guessing"
        ]

    if solution != grid:
        return False, messages + ["FAIL: solver produced a different grid (ambiguous clues)"]

    empty_lines = sum(1 for c in row_clues if not c) + sum(1 for c in col_clues if not c)
    if empty_lines > (width + height) * 0.25:
        messages.append(f"warn: {empty_lines} fully-empty lines -- consider tightening")

    return True, messages


# --------------------------------------------------------------------------
# Emit
# --------------------------------------------------------------------------

def lua_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def emit_lua(packs):
    lines = [
        "-- Generated by build_puzzles.py -- do not edit by hand.",
        "-- Run `python3 build_puzzles.py` after editing puzzles/*.txt",
        "",
        "PUZZLE_PACKS = {",
    ]
    for pack_name, puzzles in packs:
        lines.append(f'\t{{ name = "{lua_escape(pack_name)}", puzzles = {{')
        for p in puzzles:
            grid = "".join("1" if c == "#" else "0" for row in p["rows"] for c in row)
            lines.append(
                f'\t\t{{ title = "{lua_escape(p["title"])}", '
                f'width = {p["width"]}, height = {p["height"]}, '
                f'grid = "{grid}" }},'
            )
        lines.append("\t} },")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main():
    if not PUZZLE_DIR.is_dir():
        print(f"error: {PUZZLE_DIR} not found", file=sys.stderr)
        return 1

    paths = sorted(PUZZLE_DIR.glob("*.txt"))
    if not paths:
        print(f"error: no .txt packs in {PUZZLE_DIR}", file=sys.stderr)
        return 1

    packs = []
    total = 0
    failures = 0

    for path in paths:
        try:
            pack_name, puzzles = parse_pack(path)
        except ParseError as e:
            print(f"  {e}", file=sys.stderr)
            failures += 1
            continue

        print(f"\n{pack_name}  ({path.name})")
        accepted = []
        for p in puzzles:
            total += 1
            ok, messages = validate(p)
            label = f"{p['title']} ({p['width']}x{p['height']})"
            if ok:
                accepted.append(p)
                note = "  " + "; ".join(messages) if messages else ""
                print(f"  ok    {label}{note}")
            else:
                failures += 1
                print(f"  FAIL  {label}")
                for m in messages:
                    print(f"          {m}")

        if accepted:
            packs.append((pack_name, accepted))

    accepted_count = sum(len(p) for _, p in packs)
    print(f"\n{accepted_count}/{total} puzzles accepted across {len(packs)} pack(s)")

    if failures:
        print(f"{failures} puzzle(s) rejected -- fix them before shipping", file=sys.stderr)

    LUA_OUT.parent.mkdir(parents=True, exist_ok=True)
    LUA_OUT.write_text(emit_lua(packs))
    print(f"wrote {LUA_OUT.relative_to(ROOT)}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
