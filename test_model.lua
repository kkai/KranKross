-- Headless tests for the Lua model and board geometry.
--
--   lua test_model.lua
--
-- The Playdate runtime is stubbed just far enough to load model/*.lua and
-- ui/board.lua. Two things are checked:
--
--   1. The model -- clue derivation cross-checked against build_puzzles.py.
--      If the two disagree the game rejects correct solves on device.
--   2. Board geometry -- that no clue tile overlaps another, intrudes into the
--      grid, or escapes the screen, for every puzzle at every zoom level.
--      The shipped build had clue numbers overlapping by 2px and bleeding into
--      the first grid row because nothing checked this.
--
-- The geometry test calls Board's real rect functions rather than reimplementing
-- them, so it cannot drift from what is actually drawn.

-- ------------------------------------------------------------ playdate stubs

function class(name)
	local cls = {}
	cls.__index = cls
	_G[name] = setmetatable(cls, {
		__call = function(c, ...)
			local o = setmetatable({}, c)
			o:init(...)
			return o
		end,
	})
	return { extends = function() return cls end }
end

table.create = function() return {} end

local noop = function() end
local fake_store = {}
playdate = {
	graphics = {
		imagetable = { new = function() return { drawImage = noop } end },
		getSystemFont = function() return {} end,
	},
	datastore = {
		read = function(key) return fake_store[key] end,
		write = function(value, key) fake_store[key] = value end,
	},
}

-- Playdate's Lua allows `x += 1`; stock Lua does not, so the sources are
-- pre-processed before loading.
local function load_playdate_lua(path)
	local f = assert(io.open(path, "r"))
	local src = f:read("a")
	f:close()
	src = src:gsub("([%w_%.%[%]]+)%s*%+=%s*([^\n]+)", "%1 = %1 + (%2)")
	src = src:gsub("([%w_%.%[%]]+)%s*%-=%s*([^\n]+)", "%1 = %1 - (%2)")
	local chunk = assert(load(src, "@" .. path))
	return chunk()
end

load_playdate_lua("source/constants.lua")
load_playdate_lua("source/model/puzzle.lua")
load_playdate_lua("source/model/numbers.lua")
load_playdate_lua("source/model/progress.lua")
load_playdate_lua("source/ui/board.lua")
load_playdate_lua("source/puzzles.lua")

-- ------------------------------------------------------------------- helpers

local failures = {}

local function check(name, cond, detail)
	if cond then
		print("  ok    " .. name)
	else
		print("  FAIL  " .. name .. "  " .. tostring(detail or ""))
		failures[#failures + 1] = name
	end
end

local function runs_string(runs)
	if #runs == 0 then return "-" end
	return table.concat(runs, ",")
end

local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w
		and a.y < b.y + b.h and b.y < a.y + a.h
end

-- ------------------------------------------------------------ decode / index

print("Puzzle decoding")

local plus = Puzzle({ title = "Plus", width = 3, height = 3, grid = "010111010" }, "Test")
check("width/height", plus.width == 3 and plus.height == 3)
check("index is row-major", plus:index(2, 3) == 8, plus:index(2, 3))
check("digit string decoded", plus.solution[2] == 1 and plus.solution[1] == 0)
check("solution length", #plus.solution == 9, #plus.solution)

print("\nClue derivation")

local nums = Numbers(plus)
check("row clues", runs_string(nums.left[1]) == "1" and runs_string(nums.left[2]) == "3")
check("col clues", runs_string(nums.top[2]) == "3", runs_string(nums.top[2]))
check("max_left", nums.max_left == 1, nums.max_left)
check("max_top", nums.max_top == 1, nums.max_top)

print("\nSolve detection")

local player = plus:new_player_grid()
check("fresh grid is empty", player[1] == EMPTY and #player == 9)
check("empty grid is not solved", not plus:is_solved(player))

for i = 1, 9 do
	player[i] = plus.solution[i] == 1 and FILLED or EMPTY
end
check("correct grid is solved", plus:is_solved(player))

for i = 1, 9 do
	if player[i] == EMPTY then player[i] = CROSSED end
end
check("crosses do not break the solve", plus:is_solved(player))

player[1] = FILLED
check("an extra filled cell breaks the solve", not plus:is_solved(player))

print("\nLine completion tracking")

local player2 = plus:new_player_grid()
check("row 2 not complete when empty", not nums:is_row_complete(player2, 2))
player2[plus:index(1, 2)] = FILLED
player2[plus:index(2, 2)] = FILLED
player2[plus:index(3, 2)] = FILLED
check("row 2 complete when filled", nums:is_row_complete(player2, 2))
player2[plus:index(1, 2)] = EMPTY
check("row 2 incomplete again", not nums:is_row_complete(player2, 2))

-- ------------------------------------- cross-check against build_puzzles.py

print("\nShipped puzzles: every puzzle round-trips through Numbers")

local count, bad = 0, 0
for _, pack in ipairs(PUZZLE_PACKS) do
	for _, def in ipairs(pack.puzzles) do
		count = count + 1
		local p = Puzzle(def, pack.name)
		local n = Numbers(p)

		local grid = p:new_player_grid()
		for i = 1, #p.solution do
			grid[i] = p.solution[i] == 1 and FILLED or EMPTY
		end

		for y = 1, p.height do
			if not n:is_row_complete(grid, y) then
				bad = bad + 1
				print("        row " .. y .. " incomplete in " .. def.title)
			end
		end
		for x = 1, p.width do
			if not n:is_column_complete(grid, x) then
				bad = bad + 1
				print("        col " .. x .. " incomplete in " .. def.title)
			end
		end
		if not p:is_solved(grid) then
			bad = bad + 1
			print("        not solved: " .. def.title)
		end
	end
end

check(count .. " puzzles loaded", count > 0, count)
check("all puzzles self-consistent", bad == 0, bad .. " problem(s)")

-- --------------------------------------------------------- board geometry

print("\nProgression gate")

fake_store[SAVE_KEY] = nil
local order = { "P/one", "P/two", "P/three" }
local prog = Progress()

check("first puzzle is always open", prog:is_unlocked(order, 1))
check("second is locked before the first is solved", not prog:is_unlocked(order, 2))
check("third is locked too", not prog:is_unlocked(order, 3))
check("frontier starts at 1", prog:frontier(order) == 1, prog:frontier(order))

prog:record(order[1], 12345)
check("second unlocks once the first is solved", prog:is_unlocked(order, 2))
check("third is still locked", not prog:is_unlocked(order, 3))
check("frontier advances", prog:frontier(order) == 2, prog:frontier(order))
check("solving does not unlock everything", not prog:is_unlocked(order, 3))

prog:record(order[2], 999)
check("third unlocks in turn", prog:is_unlocked(order, 3))
check("best time is retained", prog:best_time(order[1]) == 12345, prog:best_time(order[1]))
check("solved count tracks", prog:solved_count() == 2, prog:solved_count())

-- A slower run must not overwrite a better time.
check("slower run is not a record", prog:record(order[1], 99999) == false)
check("best time unchanged after slower run", prog:best_time(order[1]) == 12345)
check("faster run is a record", prog:record(order[1], 5000) == true)
check("best time improved", prog:best_time(order[1]) == 5000)

-- Progress must survive a reload from the datastore.
local reloaded = Progress()
check("progress persists across reload", reloaded:is_solved(order[1]) and reloaded:is_solved(order[2]))
check("reloaded gate still opens the third", reloaded:is_unlocked(order, 3))
check("reloaded frontier is the third", reloaded:frontier(order) == 3, reloaded:frontier(order))
fake_store[SAVE_KEY] = nil

print("\nZoom table sanity")

local zoom_bad = {}
for level, spec in ipairs(ZOOM_LEVELS) do
	-- A clue tile must be no taller than a cell, or stacked rows collide in
	-- the left gutter; and exactly as wide as a cell, or top-gutter tiles
	-- drift out of alignment with their column.
	if spec.clue_h > spec.cell then
		zoom_bad[#zoom_bad + 1] = spec.name .. ": clue_h " .. spec.clue_h .. " > cell " .. spec.cell
	end
	if spec.clue_w ~= spec.cell then
		zoom_bad[#zoom_bad + 1] = spec.name .. ": clue_w " .. spec.clue_w .. " ~= cell " .. spec.cell
	end
end
check("clue tiles fit their cells", #zoom_bad == 0, table.concat(zoom_bad, "; "))

print("\nBoard layout: no overlap, no intrusion, on screen")

local problems = {}
local checked = 0

local function record(puzzle, level, msg)
	problems[#problems + 1] = string.format("%s @%s: %s",
		puzzle.title, ZOOM_LEVELS[level].name, msg)
end

for _, pack in ipairs(PUZZLE_PACKS) do
	for _, def in ipairs(pack.puzzles) do
		local p = Puzzle(def, pack.name)
		local n = Numbers(p)

		for level = 1, #ZOOM_LEVELS do
			local board = Board(p, n, level)
			board:set_zoom(level)
			local g = board.g

			-- Exercise the extremes of the camera as well as the origin.
			local scrolls = {
				{ 0, 0 },
				{ g.grid_w, g.grid_h },              -- clamped to max
				{ g.grid_w // 2, g.grid_h // 2 },
			}

			for _, s in ipairs(scrolls) do
				board.scroll_x, board.scroll_y = s[1], s[2]
				board:_clamp_scroll()
				local bx, by = board:board_origin()
				checked = checked + 1

				-- Left gutter: rects within a row must not overlap, and rows
				-- are separated because the pitch is a full cell.
				for y = 1, p.height do
					local runs = n.left[y]
					local rects = {}
					for i = 1, #runs do
						local x, ry, w, h = board:left_clue_rect(y, i, #runs, by)
						rects[#rects + 1] = { x = x, y = ry, w = w, h = h }
						if runs[i] > MAX_CLUE_TILE then
							record(p, level, "clue " .. runs[i] .. " has no tile")
						end
						if x < 0 then
							record(p, level, "left clue off screen at row " .. y)
						end
						if x + w > g.view_x0 then
							record(p, level, "left clue intrudes into grid at row " .. y)
						end
					end
					for a = 1, #rects do
						for b = a + 1, #rects do
							if overlaps(rects[a], rects[b]) then
								record(p, level, "left clues overlap at row " .. y)
							end
						end
					end
				end

				-- Top gutter.
				for x = 1, p.width do
					local runs = n.top[x]
					local rects = {}
					for i = 1, #runs do
						local rx, ry, w, h = board:top_clue_rect(x, i, #runs, bx)
						rects[#rects + 1] = { x = rx, y = ry, w = w, h = h }
						if runs[i] > MAX_CLUE_TILE then
							record(p, level, "clue " .. runs[i] .. " has no tile")
						end
						if ry < HUD_H then
							record(p, level, "top clue intrudes into HUD at col " .. x)
						end
						if ry + h > g.view_y0 then
							record(p, level, "top clue intrudes into grid at col " .. x)
						end
					end
					for a = 1, #rects do
						for b = a + 1, #rects do
							if overlaps(rects[a], rects[b]) then
								record(p, level, "top clues overlap at col " .. x)
							end
						end
					end
				end

				-- The board must never be scrolled past its own edges.
				if bx > g.view_x0 and board:scrolls_x() then
					record(p, level, "scrolled past left edge")
				end
				if by > g.view_y0 and board:scrolls_y() then
					record(p, level, "scrolled past top edge")
				end

				-- Gutters must sit flush against the board, not float away
				-- from it. When an axis scrolls the gutter pins to the screen
				-- edge and a gap is correct; when it does not, any gap means
				-- the clues have detached from the rows they label.
				if not board:scrolls_x() then
					for y = 1, p.height do
						local runs = n.left[y]
						if #runs > 0 then
							local x, _, w = board:left_clue_rect(y, #runs, #runs, by)
							if x + w ~= bx then
								record(p, level, "left gutter detached at row " .. y
									.. " (" .. (bx - x - w) .. "px gap)")
							end
						end
					end
				end
				if not board:scrolls_y() then
					for x = 1, p.width do
						local runs = n.top[x]
						if #runs > 0 then
							local _, ry, _, h = board:top_clue_rect(x, #runs, #runs, bx)
							if ry + h ~= by then
								record(p, level, "top gutter detached at col " .. x
									.. " (" .. (by - ry - h) .. "px gap)")
							end
						end
					end
				end
			end
		end
	end
end

check(checked .. " layout configurations checked", checked > 0, checked)
check("no layout problems", #problems == 0,
	#problems .. " problem(s): " .. table.concat(problems, " | ", 1, math.min(#problems, 5)))

print("\nDefault zoom picks the largest level that fits")

local fit_bad = {}
for _, pack in ipairs(PUZZLE_PACKS) do
	for _, def in ipairs(pack.puzzles) do
		local p = Puzzle(def, pack.name)
		local n = Numbers(p)
		local board = Board(p, n)
		local g = board.g
		local fits = g.content_w <= SCREEN_W and g.content_h <= SCREEN_H - HUD_H
		-- If it fits it must not scroll; if it doesn't, Overview is the floor.
		if fits and (board:scrolls_x() or board:scrolls_y()) then
			fit_bad[#fit_bad + 1] = def.title .. " fits but scrolls"
		end
		if not fits and board.zoom ~= ZOOM_OVERVIEW then
			fit_bad[#fit_bad + 1] = def.title .. " overflows above Overview"
		end
	end
end
check("default zoom is consistent", #fit_bad == 0, table.concat(fit_bad, "; "))

print()
if #failures > 0 then
	print(#failures .. " test(s) failed: " .. table.concat(failures, ", "))
	os.exit(1)
end
print("all tests passed")
