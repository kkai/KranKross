-- Clue derivation.
--
-- Approach adapted from "Sketch, Share, Solve" (MIT, (c) 2022 Rebecca Koenig),
-- https://codeberg.org/monometric/sketch-share-solve -- a single scan per line
-- producing both the run lengths and where each run starts. The start indexes
-- are what let the UI dim a clue once the player has satisfied it.

class("Numbers").extends()

function Numbers:init(puzzle)
	self.puzzle = puzzle
	self.left = table.create(puzzle.height, 0)
	self.top = table.create(puzzle.width, 0)

	for y = 1, puzzle.height do
		self.left[y] = self:_row_runs(y)
	end
	for x = 1, puzzle.width do
		self.top[x] = self:_column_runs(x)
	end

	self.max_left = 1
	for y = 1, puzzle.height do
		self.max_left = math.max(self.max_left, #self.left[y])
	end

	self.max_top = 1
	for x = 1, puzzle.width do
		self.max_top = math.max(self.max_top, #self.top[x])
	end
end

function Numbers:_row_runs(y)
	local runs = {}
	local count = 0
	local puzzle = self.puzzle
	for x = 1, puzzle.width do
		if puzzle.solution[puzzle:index(x, y)] == 1 then
			count += 1
		elseif count > 0 then
			table.insert(runs, count)
			count = 0
		end
	end
	if count > 0 then
		table.insert(runs, count)
	end
	return runs
end

function Numbers:_column_runs(x)
	local runs = {}
	local count = 0
	local puzzle = self.puzzle
	for y = 1, puzzle.height do
		if puzzle.solution[puzzle:index(x, y)] == 1 then
			count += 1
		elseif count > 0 then
			table.insert(runs, count)
			count = 0
		end
	end
	if count > 0 then
		table.insert(runs, count)
	end
	return runs
end

-- Run lengths the player has actually drawn in a line, so the UI can compare
-- them against the clues and grey out the ones that match.
function Numbers:player_row_runs(player, y)
	local runs = {}
	local count = 0
	local puzzle = self.puzzle
	for x = 1, puzzle.width do
		if player[puzzle:index(x, y)] == FILLED then
			count += 1
		elseif count > 0 then
			table.insert(runs, count)
			count = 0
		end
	end
	if count > 0 then
		table.insert(runs, count)
	end
	return runs
end

function Numbers:player_column_runs(player, x)
	local runs = {}
	local count = 0
	local puzzle = self.puzzle
	for y = 1, puzzle.height do
		if player[puzzle:index(x, y)] == FILLED then
			count += 1
		elseif count > 0 then
			table.insert(runs, count)
			count = 0
		end
	end
	if count > 0 then
		table.insert(runs, count)
	end
	return runs
end

local function runs_match(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

function Numbers:is_row_complete(player, y)
	return runs_match(self.left[y], self:player_row_runs(player, y))
end

function Numbers:is_column_complete(player, x)
	return runs_match(self.top[x], self:player_column_runs(player, x))
end
