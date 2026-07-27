-- A single nonogram.
--
-- The grid is a flat, row-major array: index = x + (y - 1) * width. Puzzle
-- definitions store it as a digit string ("0110...") which is compact in the
-- source tree and cheap to decode.

class("Puzzle").extends()

function Puzzle:init(def, pack_name)
	self.title = def.title
	self.pack = pack_name
	self.width = def.width
	self.height = def.height

	local size = self.width * self.height
	self.solution = table.create(size, 0)

	local bytes = { string.byte(def.grid, 1, size) }
	for i = 1, size do
		self.solution[i] = bytes[i] - 48
	end
end

function Puzzle:index(x, y)
	return x + (y - 1) * self.width
end

function Puzzle:id()
	return self.pack .. "/" .. self.title
end

-- The player's crosses are just notes, so only filled cells are compared.
function Puzzle:is_solved(player)
	local solution = self.solution
	for i = 1, self.width * self.height do
		local filled = player[i] == FILLED and 1 or 0
		if filled ~= solution[i] then
			return false
		end
	end
	return true
end

function Puzzle:new_player_grid()
	local grid = table.create(self.width * self.height, 0)
	for i = 1, self.width * self.height do
		grid[i] = EMPTY
	end
	return grid
end
