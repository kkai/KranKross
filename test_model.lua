-- Headless tests for the Lua model, run with the stock lua interpreter.
--
--   lua test_model.lua
--
-- The Playdate runtime is stubbed just far enough to load model/*.lua. This
-- exists to cross-check the Lua clue derivation against build_puzzles.py --
-- if the two disagree, the game will reject correct solves on device and the
-- only symptom is an angry player.

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

-- Playdate's Lua allows `x += 1`; stock Lua does not, so the sources are
-- pre-processed before loading.
local function load_playdate_lua(path)
	local f = assert(io.open(path, "r"))
	local src = f:read("a")
	f:close()
	src = src:gsub("([%w_%.%[%]]+)%s*%+=%s*([^\n]+)", "%1 = %1 + (%2)")
	local chunk = assert(load(src, "@" .. path))
	return chunk()
end

load_playdate_lua("source/constants.lua")

load_playdate_lua("source/model/puzzle.lua")
load_playdate_lua("source/model/numbers.lua")
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

-- Crosses are notes; they must not affect the win check.
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

		if #p.solution ~= p.width * p.height then
			bad = bad + 1
			print("        length mismatch: " .. def.title)
		end

		-- Filling in the solution must complete every row and column.
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

print("\nGutter sizing fits the 400x240 screen")

-- CELL / CLUE_W / CLUE_H come from source/constants.lua, so tightening the
-- layout there is checked against every shipped puzzle here.
local overflow = {}
for _, pack in ipairs(PUZZLE_PACKS) do
	for _, def in ipairs(pack.puzzles) do
		local p = Puzzle(def, pack.name)
		local n = Numbers(p)
		local w = n.max_left * CLUE_W + p.width * CELL
		local h = n.max_top * CLUE_H + p.height * CELL
		if w > 400 or h > 240 then
			overflow[#overflow + 1] = string.format("%s (%dx%d px)", def.title, w, h)
		end
	end
end
check("no puzzle overflows", #overflow == 0, table.concat(overflow, ", "))

print()
if #failures > 0 then
	print(#failures .. " test(s) failed: " .. table.concat(failures, ", "))
	os.exit(1)
end
print("all tests passed")
