-- Per-puzzle completion times, persisted via playdate.datastore.
-- Structure mirrors CranKen's best_times.lua, keyed by puzzle id instead of
-- grid size.

local pd <const> = playdate

class("Progress").extends()

function Progress:init()
	local saved = pd.datastore.read(SAVE_KEY)
	self.best = (saved and saved.best) or {}
end

function Progress:best_time(puzzle_id)
	return self.best[puzzle_id]
end

function Progress:is_solved(puzzle_id)
	return self.best[puzzle_id] ~= nil
end

-- Returns true when this run beat the stored time (or was the first clear).
function Progress:record(puzzle_id, time_ms)
	local previous = self.best[puzzle_id]
	if previous and previous <= time_ms then
		return false
	end

	self.best[puzzle_id] = time_ms
	self:_save()
	return true
end

-- Puzzles unlock in order: you cannot start one until the previous is solved.
-- Kept as a pure function of the id list so it is testable headlessly.
function Progress:is_unlocked(ordered_ids, index)
	if index <= 1 then
		return true
	end
	return self:is_solved(ordered_ids[index - 1])
end

-- Index of the first puzzle not yet solved -- where the player is up to.
function Progress:frontier(ordered_ids)
	for i = 1, #ordered_ids do
		if not self:is_solved(ordered_ids[i]) then
			return i
		end
	end
	return #ordered_ids
end

function Progress:solved_count()
	local count = 0
	for _ in pairs(self.best) do
		count += 1
	end
	return count
end

function Progress:_save()
	pd.datastore.write({ best = self.best }, SAVE_KEY)
end

function Progress.format_time(time_ms)
	if not time_ms then
		return "--:--"
	end
	local seconds = math.floor(time_ms / 1000)
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end
