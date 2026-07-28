-- Board rendering: pinned clue gutters, scrolling grid, cursor.
--
-- Layout contract, enforced by the geometry assertions in test_model.lua:
--
--   * Clue numbers are pre-rendered tiles, never drawText. A tile is exactly
--     one slot wide and one slot tall, so two-digit clues cannot bleed into a
--     neighbour and stacked clues cannot overlap.
--   * Clues anchor at the board edge and grow outward, which right-aligns the
--     left gutter and bottom-aligns the top gutter for free.
--   * The left gutter is pinned horizontally and scrolls vertically with the
--     rows; the top gutter is pinned vertically and scrolls horizontally with
--     the columns. Frozen spreadsheet headers. Losing sight of your clues
--     while panning is the worst failure mode in large-grid picross.

local pd <const> = playdate
local gfx <const> = pd.graphics

class("Board").extends()

local sheets = {}

local function clue_sheet(level)
	local spec = ZOOM_LEVELS[level]
	if not sheets[level] then
		sheets[level] = gfx.imagetable.new(spec.sheet)
		assert(sheets[level], "missing clue tiles: " .. spec.sheet)
	end
	return sheets[level]
end

function Board:init(puzzle, numbers, zoom)
	self.puzzle = puzzle
	self.numbers = numbers
	self.scroll_x = 0
	self.scroll_y = 0
	self:set_zoom(zoom or self:default_zoom())
end

-- Largest zoom at which the whole board fits without scrolling, else Overview.
function Board:default_zoom()
	for level = #ZOOM_LEVELS, 1, -1 do
		local g = self:_geometry(level)
		if g.content_w <= SCREEN_W and g.content_h <= SCREEN_H - HUD_H then
			return level
		end
	end
	return ZOOM_OVERVIEW
end

function Board:_geometry(level)
	local spec = ZOOM_LEVELS[level]
	local puzzle = self.puzzle

	-- Gutters are sized to the puzzle's actual widest clue list, not the
	-- theoretical ceil(n/2) worst case, which would waste most of the screen.
	local left_gutter = self.numbers.max_left * spec.clue_w
	local top_gutter = self.numbers.max_top * spec.clue_h

	local grid_w = puzzle.width * spec.cell
	local grid_h = puzzle.height * spec.cell
	local content_w = left_gutter + grid_w
	local content_h = top_gutter + grid_h

	local avail_w = SCREEN_W
	local avail_h = SCREEN_H - HUD_H

	local scrolls_x = content_w > avail_w
	local scrolls_y = content_h > avail_h

	-- view_x0/view_y0 is where the grid starts, and the gutters sit directly
	-- against it. When everything fits, the whole block is centred so the
	-- clues stay attached to their rows and columns; only when the board is
	-- larger than the screen do the gutters pin to the edge and the grid
	-- scroll beneath them.
	local view_x0 = scrolls_x and left_gutter
		or ((avail_w - content_w) // 2 + left_gutter)
	local view_y0 = scrolls_y and (HUD_H + top_gutter)
		or (HUD_H + (avail_h - content_h) // 2 + top_gutter)

	return {
		spec = spec,
		left_gutter = left_gutter,
		top_gutter = top_gutter,
		grid_w = grid_w,
		grid_h = grid_h,
		content_w = content_w,
		content_h = content_h,
		scrolls_x = scrolls_x,
		scrolls_y = scrolls_y,
		view_x0 = view_x0,
		view_y0 = view_y0,
		view_w = SCREEN_W - view_x0,
		view_h = SCREEN_H - view_y0,
	}
end

function Board:set_zoom(level)
	level = math.max(1, math.min(#ZOOM_LEVELS, level))
	self.zoom = level
	self.g = self:_geometry(level)
	self.sheet = clue_sheet(level)
	self:_clamp_scroll()
end

function Board:scrolls_x() return self.g.scrolls_x end
function Board:scrolls_y() return self.g.scrolls_y end

function Board:_clamp_scroll()
	local g = self.g
	self.scroll_x = math.max(0, math.min(math.max(0, g.grid_w - g.view_w), self.scroll_x))
	self.scroll_y = math.max(0, math.min(math.max(0, g.grid_h - g.view_h), self.scroll_y))
end

-- Screen position of the grid's top-left corner. Centred within the viewport
-- when it fits, offset by the scroll when it does not.
function Board:board_origin()
	-- scroll is clamped to 0 when the axis does not scroll, so this is uniform.
	return self.g.view_x0 - self.scroll_x, self.g.view_y0 - self.scroll_y
end

-- Clue tile rectangles, kept as pure geometry so the layout assertions in
-- test_model.lua call exactly the code that draws. A duplicated copy of this
-- math in the test would be free to drift, which is how the previous layout
-- shipped broken.
--
-- Both anchor at the board edge and grow outward, which right-aligns the left
-- gutter and bottom-aligns the top gutter without any special casing.

function Board:left_clue_rect(row, i, count, board_y)
	local spec = self.g.spec
	return self.g.view_x0 - (count - i + 1) * spec.clue_w,
		board_y + (row - 1) * spec.cell + (spec.cell - spec.clue_h) // 2,
		spec.clue_w, spec.clue_h
end

function Board:top_clue_rect(col, i, count, board_x)
	local spec = self.g.spec
	return board_x + (col - 1) * spec.cell + (spec.cell - spec.clue_w) // 2,
		self.g.view_y0 - (count - i + 1) * spec.clue_h,
		spec.clue_w, spec.clue_h
end

-- Keep the cursor inside the middle DEAD_ZONE of the viewport.
function Board:follow_cursor(cursor_x, cursor_y)
	local g = self.g
	local cell = g.spec.cell

	if self:scrolls_x() then
		local margin = math.floor(g.view_w * (1 - DEAD_ZONE) / 2)
		local cx = (cursor_x - 1) * cell
		if cx < self.scroll_x + margin then
			self.scroll_x = cx - margin
		elseif cx + cell > self.scroll_x + g.view_w - margin then
			self.scroll_x = cx + cell - g.view_w + margin
		end
	end

	if self:scrolls_y() then
		local margin = math.floor(g.view_h * (1 - DEAD_ZONE) / 2)
		local cy = (cursor_y - 1) * cell
		if cy < self.scroll_y + margin then
			self.scroll_y = cy - margin
		elseif cy + cell > self.scroll_y + g.view_h - margin then
			self.scroll_y = cy + cell - g.view_h + margin
		end
	end

	self:_clamp_scroll()
end

function Board:draw(player, cursor_x, cursor_y)
	local g = self.g
	local bx, by = self:board_origin()

	self:_draw_grid(player, bx, by, cursor_x, cursor_y)
	self:_draw_left_gutter(player, by)
	self:_draw_top_gutter(player, bx)

	gfx.clearClipRect()
end

-- ------------------------------------------------------------------- grid

function Board:_draw_grid(player, bx, by, cursor_x, cursor_y)
	local g = self.g
	local cell = g.spec.cell
	local puzzle = self.puzzle

	gfx.setClipRect(g.view_x0, g.view_y0, g.view_w, g.view_h)

	-- Only the rows and columns actually on screen.
	local x0 = math.max(1, (self.scroll_x // cell) + 1)
	local y0 = math.max(1, (self.scroll_y // cell) + 1)
	local x1 = math.min(puzzle.width, x0 + (g.view_w // cell) + 1)
	local y1 = math.min(puzzle.height, y0 + (g.view_h // cell) + 1)
	if not self:scrolls_x() then x0, x1 = 1, puzzle.width end
	if not self:scrolls_y() then y0, y1 = 1, puzzle.height end

	for y = y0, y1 do
		for x = x0, x1 do
			local state = player[puzzle:index(x, y)]
			local cx = bx + (x - 1) * cell
			local cy = by + (y - 1) * cell
			if state == FILLED then
				gfx.fillRect(cx, cy, cell, cell)
			elseif state == CROSSED then
				local m = cell >= 16 and 5 or (cell >= 12 and 3 or 2)
				gfx.setLineWidth(1)
				gfx.drawLine(cx + m, cy + m, cx + cell - m, cy + cell - m)
				gfx.drawLine(cx + cell - m, cy + m, cx + m, cy + cell - m)
			end
		end
	end

	self:_draw_grid_lines(bx, by, x0, x1, y0, y1)
	self:_draw_cursor(bx, by, cursor_x, cursor_y)
end

function Board:_draw_grid_lines(bx, by, x0, x1, y0, y1)
	local g = self.g
	local cell = g.spec.cell
	local top = by + (y0 - 1) * cell
	local bottom = by + y1 * cell
	local left = bx + (x0 - 1) * cell
	local right = bx + x1 * cell

	gfx.setLineWidth(1)
	for x = x0 - 1, x1 do
		if x % 5 ~= 0 then
			gfx.drawLine(bx + x * cell, top, bx + x * cell, bottom)
		end
	end
	for y = y0 - 1, y1 do
		if y % 5 ~= 0 then
			gfx.drawLine(left, by + y * cell, right, by + y * cell)
		end
	end

	-- Every fifth line heavy, so runs can be counted at a glance.
	gfx.setLineWidth(2)
	for x = x0 - 1, x1 do
		if x % 5 == 0 then
			gfx.drawLine(bx + x * cell, top, bx + x * cell, bottom)
		end
	end
	for y = y0 - 1, y1 do
		if y % 5 == 0 then
			gfx.drawLine(left, by + y * cell, right, by + y * cell)
		end
	end
	gfx.setLineWidth(1)
end

function Board:_draw_cursor(bx, by, x, y)
	local cell = self.g.spec.cell
	local cx = bx + (x - 1) * cell
	local cy = by + (y - 1) * cell
	gfx.setLineWidth(1)
	gfx.setColor(gfx.kColorXOR)
	gfx.drawRect(cx, cy, cell, cell)
	if cell >= 12 then
		gfx.drawRect(cx + 1, cy + 1, cell - 2, cell - 2)
	end
	gfx.setColor(gfx.kColorBlack)
end

-- ----------------------------------------------------------------- gutters

-- Left gutter: x pinned to the screen edge, y follows the scrolled rows.
function Board:_draw_left_gutter(player, by)
	local g = self.g
	local cell, clue_w, clue_h = g.spec.cell, g.spec.clue_w, g.spec.clue_h
	if g.left_gutter == 0 then return end

	gfx.setClipRect(g.view_x0 - g.left_gutter, g.view_y0, g.left_gutter, g.view_h)

	for y = 1, self.puzzle.height do
		local runs = self.numbers.left[y]
		if #runs > 0 then
			local _, ty = self:left_clue_rect(y, #runs, #runs, by)
			if ty + clue_h > g.view_y0 and ty < SCREEN_H then
				for i = 1, #runs do
					local tx, tty = self:left_clue_rect(y, i, #runs, by)
					self:_draw_clue(runs[i], tx, tty)
				end
				if self.numbers:is_row_complete(player, y) then
					local from = g.view_x0 - #runs * clue_w
					gfx.drawLine(from, ty + clue_h // 2, g.view_x0 - 1, ty + clue_h // 2)
				end
			end
		end
	end
end

-- Top gutter: y pinned below the HUD, x follows the scrolled columns.
function Board:_draw_top_gutter(player, bx)
	local g = self.g
	local cell, clue_w, clue_h = g.spec.cell, g.spec.clue_w, g.spec.clue_h
	if g.top_gutter == 0 then return end

	gfx.setClipRect(g.view_x0, g.view_y0 - g.top_gutter, g.view_w, g.top_gutter)

	for x = 1, self.puzzle.width do
		local runs = self.numbers.top[x]
		if #runs > 0 then
			local tx = self:top_clue_rect(x, #runs, #runs, bx)
			if tx + clue_w > g.view_x0 and tx < SCREEN_W then
				for i = 1, #runs do
					local ttx, ty = self:top_clue_rect(x, i, #runs, bx)
					self:_draw_clue(runs[i], ttx, ty)
				end
				if self.numbers:is_column_complete(player, x) then
					local from = g.view_y0 - #runs * clue_h
					gfx.drawLine(tx + clue_w // 2, from, tx + clue_w // 2, g.view_y0 - 1)
				end
			end
		end
	end
end

function Board:_draw_clue(value, x, y)
	if value >= 1 and value <= MAX_CLUE_TILE then
		self.sheet:drawImage(value, x, y)
	end
end
