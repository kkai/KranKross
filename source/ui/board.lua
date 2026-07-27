-- Board rendering: clue gutters, grid, cell states, cursor.

local pd <const> = playdate
local gfx <const> = pd.graphics

class("Board").extends()

function Board:init(puzzle, numbers)
	self.puzzle = puzzle
	self.numbers = numbers

	self.left_gutter = numbers.max_left * CLUE_W
	self.top_gutter = numbers.max_top * CLUE_H

	local total_w = self.left_gutter + puzzle.width * CELL
	local total_h = self.top_gutter + puzzle.height * CELL

	self.origin_x = math.floor((400 - total_w) / 2) + self.left_gutter
	self.origin_y = math.floor((240 - total_h) / 2) + self.top_gutter

	-- The system font is used everywhere; cache it rather than relying on
	-- gfx.getFont() round-trips, which are a no-op reset.
	self.font = gfx.getSystemFont()
end

function Board:cell_rect(x, y)
	return self.origin_x + (x - 1) * CELL, self.origin_y + (y - 1) * CELL
end

function Board:draw(player, cursor_x, cursor_y)
	gfx.setFont(self.font)
	self:_draw_clues(player)
	self:_draw_cells(player)
	self:_draw_grid_lines()
	self:_draw_cursor(cursor_x, cursor_y)
end

function Board:_draw_clues(player)
	local puzzle = self.puzzle
	local numbers = self.numbers

	gfx.setImageDrawMode(gfx.kDrawModeCopy)

	-- An empty line draws nothing at all. Showing "0" is technically correct
	-- but fills the gutters of sparse puzzles with noise.
	for y = 1, puzzle.height do
		local runs = numbers.left[y]
		if #runs > 0 then
			local done = numbers:is_row_complete(player, y)
			local cy = self.origin_y + (y - 1) * CELL + math.floor((CELL - 12) / 2)
			local left = self.origin_x
			for i = #runs, 1, -1 do
				local text = tostring(runs[i])
				local w = gfx.getTextSize(text)
				local cx = self.origin_x - (#runs - i + 1) * CLUE_W + (CLUE_W - w)
				gfx.drawText(text, cx, cy)
				left = math.min(left, cx)
			end
			if done then
				self:_strike(left, self.origin_x - 2, cy + 6)
			end
		end
	end

	for x = 1, puzzle.width do
		local runs = numbers.top[x]
		if #runs > 0 then
			local done = numbers:is_column_complete(player, x)
			local top = self.origin_y
			local cx_center = self.origin_x + (x - 1) * CELL
			for i = #runs, 1, -1 do
				local text = tostring(runs[i])
				local w = gfx.getTextSize(text)
				local cx = cx_center + math.floor((CELL - w) / 2)
				local cy = self.origin_y - (#runs - i + 1) * CLUE_H + 1
				gfx.drawText(text, cx, cy)
				top = math.min(top, cy)
			end
			if done then
				self:_strike_v(cx_center + CELL // 2, top, self.origin_y - 2)
			end
		end
	end
end

-- Satisfied clues get struck through rather than dimmed. On a 1-bit screen a
-- greyed or outlined number is harder to read than a struck one, and the
-- strike is the convention players already know from paper nonograms.
function Board:_strike(x0, x1, y)
	gfx.setLineWidth(1)
	gfx.drawLine(x0 - 1, y, x1, y)
end

function Board:_strike_v(x, y0, y1)
	gfx.setLineWidth(1)
	gfx.drawLine(x, y0 - 1, x, y1)
end

function Board:_draw_cells(player)
	local puzzle = self.puzzle
	for y = 1, puzzle.height do
		for x = 1, puzzle.width do
			local state = player[puzzle:index(x, y)]
			local cx, cy = self:cell_rect(x, y)

			if state == FILLED then
				gfx.fillRect(cx, cy, CELL, CELL)
			elseif state == CROSSED then
				gfx.setLineWidth(1)
				gfx.drawLine(cx + 5, cy + 5, cx + CELL - 5, cy + CELL - 5)
				gfx.drawLine(cx + CELL - 5, cy + 5, cx + 5, cy + CELL - 5)
			end
		end
	end
end

function Board:_draw_grid_lines()
	local puzzle = self.puzzle
	local x0, y0 = self.origin_x, self.origin_y
	local x1 = x0 + puzzle.width * CELL
	local y1 = y0 + puzzle.height * CELL

	gfx.setLineWidth(1)
	for x = 0, puzzle.width do
		gfx.drawLine(x0 + x * CELL, y0, x0 + x * CELL, y1)
	end
	for y = 0, puzzle.height do
		gfx.drawLine(x0, y0 + y * CELL, x1, y0 + y * CELL)
	end

	-- Every fifth line is drawn heavy so the eye can count runs at a glance.
	gfx.setLineWidth(2)
	for x = 0, puzzle.width, 5 do
		gfx.drawLine(x0 + x * CELL, y0, x0 + x * CELL, y1)
	end
	for y = 0, puzzle.height, 5 do
		gfx.drawLine(x0, y0 + y * CELL, x1, y0 + y * CELL)
	end
	gfx.setLineWidth(1)
end

-- Drawn strictly inside the cell: a cursor that overhangs bleeds into the
-- clue gutter on the top and left edges and reads as a rendering artifact.
function Board:_draw_cursor(x, y)
	local cx, cy = self:cell_rect(x, y)
	gfx.setLineWidth(1)
	gfx.setColor(gfx.kColorXOR)
	gfx.drawRect(cx, cy, CELL, CELL)
	gfx.drawRect(cx + 1, cy + 1, CELL - 2, CELL - 2)
	gfx.setColor(gfx.kColorBlack)
end
