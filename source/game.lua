-- Game controller: puzzle selection, solving, completion.

local pd <const> = playdate
local gfx <const> = pd.graphics

local VISIBLE_ROWS <const> = 7
local ROW_H <const> = 22

-- Selection row layout. The title column is a redaction bar until solved:
-- naming the picture in the list would give away the very thing the puzzle
-- exists to reveal.
local THUMB_BOX <const> = 20
local ICON_X <const> = 16
local LABEL_X <const> = 42
local TITLE_X <const> = 84
local META_RIGHT <const> = 380
local REDACT_W <const> = 132

-- Held-button auto-repeat. Without this, crossing a 20-wide grid or a 33-entry
-- puzzle list means 20 or 33 discrete presses.
local REPEAT_DELAY <const> = 12
local REPEAT_RATE <const> = 4

class("Game").extends()

function Game:init()
	self.progress = Progress()

	-- Flatten the packs into one scrolling list, with pack names as headers.
	-- `order` is the puzzle's position in the flat sequence, which is what the
	-- unlock gate walks; `label` is its catalogue number, shown instead of the
	-- title until the puzzle is solved.
	self.entries = {}
	self.order = {}
	for pack_index, pack in ipairs(PUZZLE_PACKS) do
		table.insert(self.entries, { header = pack.name })
		for index_in_pack, def in ipairs(pack.puzzles) do
			local puzzle = Puzzle(def, pack.name)
			table.insert(self.order, puzzle:id())
			table.insert(self.entries, {
				puzzle = puzzle,
				order = #self.order,
				label = string.format("%d-%02d", pack_index, index_in_pack),
			})
		end
	end

	self.selected = 2 -- skip the first header
	self.scroll = 0
	self.state = STATE_SELECT
	self.needs_redraw = true
	self.held = {}
end

-- True on the initial press, then again at a steady rate while held.
function Game:_repeats(button)
	if pd.buttonJustPressed(button) then
		self.held[button] = 0
		return true
	end

	if not pd.buttonIsPressed(button) then
		self.held[button] = nil
		return false
	end

	local frames = (self.held[button] or 0) + 1
	self.held[button] = frames
	return frames >= REPEAT_DELAY and (frames - REPEAT_DELAY) % REPEAT_RATE == 0
end

function Game:update()
	if self.state == STATE_SELECT then
		self:_update_select()
	elseif self.state == STATE_PLAYING then
		self:_update_playing()
	elseif self.state == STATE_SOLVED then
		self:_update_solved()
	end
end

-- ---------------------------------------------------------------- selection

function Game:_update_select()
	local moved = false

	if self:_repeats(pd.kButtonDown) then
		moved = self:_move_selection(1)
	elseif self:_repeats(pd.kButtonUp) then
		moved = self:_move_selection(-1)
	end

	self.select_crank = (self.select_crank or 0) + pd.getCrankChange()
	while self.select_crank >= 45 do
		self.select_crank -= 45
		moved = self:_move_selection(1) or moved
	end
	while self.select_crank <= -45 do
		self.select_crank += 45
		moved = self:_move_selection(-1) or moved
	end

	if pd.buttonJustPressed(pd.kButtonA) then
		local entry = self.entries[self.selected]
		if self:_is_unlocked(entry) then
			self:_start_puzzle(entry.puzzle)
			return
		end
		-- Locked: refuse, and say why rather than silently doing nothing.
		self.locked_notice = 40
		moved = true
	end

	if self.locked_notice and self.locked_notice > 0 then
		self.locked_notice -= 1
		if self.locked_notice == 0 then
			self.locked_notice = nil
			moved = true
		end
	end

	if moved or self.needs_redraw then
		self:_draw_select()
		self.needs_redraw = false
	end
end

function Game:_is_unlocked(entry)
	return entry.puzzle ~= nil and self.progress:is_unlocked(self.order, entry.order)
end

-- A miniature of the solved picture, one or two pixels per cell, built once
-- and cached on the entry. This is the reward for finishing a puzzle: the
-- chapter list slowly fills in with the artwork you uncovered.
function Game:_thumbnail(entry)
	if entry.thumb then
		return entry.thumb
	end

	local puzzle = entry.puzzle
	local scale = math.max(1, THUMB_BOX // math.max(puzzle.width, puzzle.height))
	local img = gfx.image.new(puzzle.width * scale, puzzle.height * scale, gfx.kColorWhite)

	gfx.pushContext(img)
	gfx.setColor(gfx.kColorBlack)
	for y = 1, puzzle.height do
		for x = 1, puzzle.width do
			if puzzle.solution[puzzle:index(x, y)] == 1 then
				gfx.fillRect((x - 1) * scale, (y - 1) * scale, scale, scale)
			end
		end
	end
	gfx.popContext()

	entry.thumb = img
	return img
end

-- Headers are skipped rather than selectable, so a step may cover two rows.
function Game:_move_selection(delta)
	local i = self.selected
	repeat
		i += delta
		if i < 1 or i > #self.entries then
			return false
		end
	until self.entries[i].puzzle

	self.selected = i
	if i - self.scroll > VISIBLE_ROWS then
		self.scroll = i - VISIBLE_ROWS
	elseif i - self.scroll < 1 then
		self.scroll = i - 1
	end
	if self.scroll > 0 and self.entries[self.scroll] and self.entries[self.scroll].header then
		self.scroll -= 1
	end
	return true
end

function Game:_draw_select()
	gfx.clear()
	gfx.setFont(gfx.getSystemFont())

	gfx.drawText("*KranKross*", 12, 8)
	local solved = string.format("%d/%d solved", self.progress:solved_count(), self:_puzzle_count())
	local w = gfx.getTextSize(solved)
	gfx.drawText(solved, 400 - w - 12, 10)
	gfx.drawLine(12, 28, 388, 28)

	for row = 1, VISIBLE_ROWS do
		local index = self.scroll + row
		local entry = self.entries[index]
		if not entry then
			break
		end

		local y = 34 + (row - 1) * ROW_H

		if entry.header then
			gfx.drawText("*" .. entry.header .. "*", 16, y + 3)
		else
			self:_draw_puzzle_row(entry, y, index == self.selected)
		end
	end

	gfx.drawLine(12, 212, 388, 212)

	local selected = self.entries[self.selected]
	local hint
	if self.locked_notice then
		hint = "Locked -- solve the puzzle before it first"
	elseif selected and not self:_is_unlocked(selected) then
		hint = "Locked    crank or d-pad: browse"
	else
		hint = "A: play    crank or d-pad: browse"
	end
	gfx.drawText(hint, 12, 218)
end

function Game:_draw_puzzle_row(entry, y, is_selected)
	local puzzle = entry.puzzle
	local id = puzzle:id()
	local solved = self.progress:is_solved(id)
	local unlocked = self:_is_unlocked(entry)

	if is_selected then
		gfx.fillRect(12, y, 376, ROW_H - 2)
		gfx.setImageDrawMode(gfx.kDrawModeInverted)
	end

	-- fillRect/drawRect ignore the image draw mode, so shapes have to flip
	-- colour by hand on a highlighted row.
	local ink = is_selected and gfx.kColorWhite or gfx.kColorBlack

	if solved then
		self:_thumbnail(entry):draw(ICON_X, y + 1)
	elseif not unlocked then
		self:_draw_lock(ICON_X + 4, y + 3, ink)
	end

	gfx.drawText(entry.label, LABEL_X, y + 3)

	if solved then
		gfx.drawText(puzzle.title, TITLE_X, y + 3)
	else
		-- Redaction bar. Hollow while locked, solid once it is your next one,
		-- so the frontier is readable at a glance.
		gfx.setColor(ink)
		if unlocked then
			gfx.fillRect(TITLE_X, y + 6, REDACT_W, 9)
		else
			gfx.setLineWidth(1)
			gfx.drawRect(TITLE_X, y + 6, REDACT_W, 9)
		end
		gfx.setColor(gfx.kColorBlack)
	end

	local meta = string.format("%dx%d", puzzle.width, puzzle.height)
	if solved then
		meta = meta .. "   " .. Progress.format_time(self.progress:best_time(id))
	end
	gfx.drawText(meta, META_RIGHT - gfx.getTextSize(meta), y + 3)

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function Game:_draw_lock(x, y, ink)
	gfx.setColor(ink)
	gfx.setLineWidth(1)
	gfx.drawRect(x + 2, y + 1, 6, 6)   -- shackle
	gfx.fillRect(x, y + 6, 10, 7)      -- body
	gfx.setColor(gfx.kColorBlack)
end

function Game:_puzzle_count()
	local n = 0
	for _, e in ipairs(self.entries) do
		if e.puzzle then
			n += 1
		end
	end
	return n
end

-- ------------------------------------------------------------------ playing

function Game:_start_puzzle(puzzle)
	self.puzzle = puzzle
	self.numbers = Numbers(puzzle)
	self.board = Board(puzzle, self.numbers)
	self.player = puzzle:new_player_grid()

	self.cursor_x = 1
	self.cursor_y = 1
	self.paint = nil
	self.zoom_accum = 0
	self.start_time = nil

	self.board:follow_cursor(self.cursor_x, self.cursor_y)
	self.state = STATE_PLAYING
	self.needs_redraw = true
end

function Game:_update_playing()
	if pd.buttonJustPressed(pd.kButtonB) and pd.buttonIsPressed(pd.kButtonA) then
		self:_abandon()
		return
	end

	local changed = false
	changed = self:_handle_zoom() or changed
	changed = self:_handle_paint() or changed
	changed = self:_handle_cursor() or changed

	if changed or self.needs_redraw then
		self.start_time = self.start_time or pd.getCurrentTimeMilliseconds()
		self:_draw_playing()
		self.needs_redraw = false

		if self.puzzle:is_solved(self.player) then
			self:_complete()
			return
		end
	elseif self.start_time then
		-- Timer needs repainting even when nothing else moved.
		self:_draw_playing()
	end
end

-- Crank drives zoom (PRD 5). It is never required: the d-pad reaches every
-- cell at any zoom level, and a docked crank blocks nothing.
function Game:_handle_zoom()
	local change = pd.getCrankChange()
	if change == 0 then
		return false
	end

	self.zoom_accum += change
	local changed = false

	while self.zoom_accum >= DEGREES_PER_ZOOM do
		self.zoom_accum -= DEGREES_PER_ZOOM
		changed = self:_step_zoom(1) or changed
	end
	while self.zoom_accum <= -DEGREES_PER_ZOOM do
		self.zoom_accum += DEGREES_PER_ZOOM
		changed = self:_step_zoom(-1) or changed
	end

	return changed
end

function Game:_step_zoom(delta)
	local target = self.board.zoom + delta
	if target < 1 or target > #ZOOM_LEVELS then
		self.zoom_accum = 0 -- don't bank travel at the ends
		return false
	end
	self.board:set_zoom(target)
	self.board:follow_cursor(self.cursor_x, self.cursor_y)
	return true
end

-- Tap A or B to toggle one cell. Hold and steer with the d-pad to drag a run
-- along a line (PRD 5) -- how nonograms are actually solved: deduce a run of
-- four, then draw four.
function Game:_handle_paint()
	if pd.buttonJustPressed(pd.kButtonA) then
		return self:_begin_paint(FILLED, pd.kButtonA)
	elseif pd.buttonJustPressed(pd.kButtonB) then
		return self:_begin_paint(CROSSED, pd.kButtonB)
	end

	if self.paint and not pd.buttonIsPressed(self.paint.button) then
		self.paint = nil
	end
	return false
end

function Game:_begin_paint(target, button)
	local index = self.puzzle:index(self.cursor_x, self.cursor_y)
	local current = self.player[index]

	-- Tapping a cell that already holds the target state erases instead, and
	-- the drag then erases along the line.
	local value = current == target and EMPTY or target

	self.paint = { value = value, button = button, axis = nil }
	self.player[index] = value
	self:_auto_cross(self.cursor_x, self.cursor_y)
	return true
end

function Game:_handle_cursor()
	local dx, dy = 0, 0
	if self:_repeats(pd.kButtonLeft) then
		dx = -1
	elseif self:_repeats(pd.kButtonRight) then
		dx = 1
	elseif self:_repeats(pd.kButtonUp) then
		dy = -1
	elseif self:_repeats(pd.kButtonDown) then
		dy = 1
	else
		return false
	end

	-- A drag locks to the axis of its first movement, so a wobbling thumb
	-- can't smear paint across two lines.
	if self.paint then
		local axis = dx ~= 0 and AXIS_H or AXIS_V
		if self.paint.axis == nil then
			self.paint.axis = axis
		elseif self.paint.axis ~= axis then
			return false
		end
	end

	local nx = math.max(1, math.min(self.puzzle.width, self.cursor_x + dx))
	local ny = math.max(1, math.min(self.puzzle.height, self.cursor_y + dy))
	if nx == self.cursor_x and ny == self.cursor_y then
		return false
	end

	self.cursor_x, self.cursor_y = nx, ny

	if self.paint then
		self.player[self.puzzle:index(nx, ny)] = self.paint.value
		self:_auto_cross(nx, ny)
	end

	self.board:follow_cursor(nx, ny)
	return true
end

-- Once a line's filled runs match its clues, the remaining cells can only be
-- empty -- crossing them saves the player a lot of bookkeeping.
--
-- Only the row and column through the cell that just changed can have become
-- complete, so only those two are rescanned. Sweeping the whole board here
-- cost width*height work per keystroke: on a 20x20 that was 40 line scans over
-- 400 cells for every single d-pad step of a drag.
function Game:_auto_cross(cx, cy)
	local puzzle = self.puzzle

	if self.numbers:is_row_complete(self.player, cy) then
		for x = 1, puzzle.width do
			local i = puzzle:index(x, cy)
			if self.player[i] == EMPTY then
				self.player[i] = CROSSED
			end
		end
	end

	if self.numbers:is_column_complete(self.player, cx) then
		for y = 1, puzzle.height do
			local i = puzzle:index(cx, y)
			if self.player[i] == EMPTY then
				self.player[i] = CROSSED
			end
		end
	end
end

function Game:_draw_playing()
	gfx.clear()
	self.board:draw(self.player, self.cursor_x, self.cursor_y)

	gfx.setFont(gfx.getSystemFont())
	gfx.setImageDrawMode(gfx.kDrawModeCopy)

	-- Grid size left, zoom centred, timer right. The pack name is deliberately
	-- absent: it is a category label, and naming the subject's category before
	-- the reveal gives the puzzle away.
	gfx.drawText(string.format("%dx%d", self.puzzle.width, self.puzzle.height), 4, -1)

	local zoom = ZOOM_LEVELS[self.board.zoom].name
	local zw = gfx.getTextSize(zoom)
	gfx.drawText(zoom, (400 - zw) // 2, -1)

	if self.start_time then
		local elapsed = pd.getCurrentTimeMilliseconds() - self.start_time
		local text = Progress.format_time(elapsed)
		local w = gfx.getTextSize(text)
		gfx.drawText(text, 400 - w - 4, -1)
	end
end

function Game:_abandon()
	self.paint = nil
	self.state = STATE_SELECT
	self.needs_redraw = true
end

-- ------------------------------------------------------------------- solved

function Game:_complete()
	self.paint = nil
	self.completion_time = pd.getCurrentTimeMilliseconds() - (self.start_time or 0)
	self.is_record = self.progress:record(self.puzzle:id(), self.completion_time)
	self.state = STATE_SOLVED

	self:_draw_playing()
	self:_draw_solved_popup()
end

function Game:_update_solved()
	if pd.buttonJustPressed(pd.kButtonA) or pd.buttonJustPressed(pd.kButtonB) then
		self.state = STATE_SELECT
		self.needs_redraw = true
	end
end

function Game:_draw_solved_popup()
	local w, h = 240, 96
	local x, y = (400 - w) // 2, (240 - h) // 2

	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(x, y, w, h)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRect(x, y, w, h)
	gfx.drawRect(x + 2, y + 2, w - 4, h - 4)

	gfx.setFont(gfx.getSystemFont())
	local function center(text, cy)
		local tw = gfx.getTextSize(text)
		gfx.drawText(text, x + (w - tw) // 2, cy)
	end

	center("*" .. self.puzzle.title .. "*", y + 14)
	center(Progress.format_time(self.completion_time), y + 38)
	center(self.is_record and "New best time!" or "Solved", y + 58)
	center("A: back to puzzles", y + 76)
end
