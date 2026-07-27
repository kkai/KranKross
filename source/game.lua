-- Game controller: puzzle selection, solving, completion.

local pd <const> = playdate
local gfx <const> = pd.graphics

local VISIBLE_ROWS <const> = 7
local ROW_H <const> = 22

-- Held-button auto-repeat. Without this, crossing a 15-wide grid or a 33-entry
-- puzzle list means 15 or 33 discrete presses.
local REPEAT_DELAY <const> = 12
local REPEAT_RATE <const> = 4

class("Game").extends()

function Game:init()
	self.progress = Progress()

	-- Flatten the packs into one scrolling list, with pack names as headers.
	self.entries = {}
	for _, pack in ipairs(PUZZLE_PACKS) do
		table.insert(self.entries, { header = pack.name })
		for _, def in ipairs(pack.puzzles) do
			table.insert(self.entries, { puzzle = Puzzle(def, pack.name) })
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
	while self.select_crank >= DEGREES_PER_CELL do
		self.select_crank -= DEGREES_PER_CELL
		moved = self:_move_selection(1) or moved
	end
	while self.select_crank <= -DEGREES_PER_CELL do
		self.select_crank += DEGREES_PER_CELL
		moved = self:_move_selection(-1) or moved
	end

	if pd.buttonJustPressed(pd.kButtonA) then
		self:_start_puzzle(self.entries[self.selected].puzzle)
		return
	end

	if moved or self.needs_redraw then
		self:_draw_select()
		self.needs_redraw = false
	end
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
	-- Pull a header into view when it sits directly above the selection.
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
			local puzzle = entry.puzzle
			local id = puzzle:id()
			local is_selected = index == self.selected

			if is_selected then
				gfx.fillRect(12, y, 376, ROW_H - 2)
				gfx.setImageDrawMode(gfx.kDrawModeInverted)
			end

			local mark = self.progress:is_solved(id) and "\u{2713} " or "  "
			gfx.drawText(mark .. puzzle.title, 28, y + 3)

			local meta = string.format("%dx%d", puzzle.width, puzzle.height)
			if self.progress:is_solved(id) then
				meta = meta .. "   " .. Progress.format_time(self.progress:best_time(id))
			end
			local mw = gfx.getTextSize(meta)
			gfx.drawText(meta, 380 - mw, y + 3)

			gfx.setImageDrawMode(gfx.kDrawModeCopy)
		end
	end

	gfx.drawLine(12, 212, 388, 212)
	gfx.drawText("A: play    crank or d-pad: browse", 12, 218)
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
	self.axis = AXIS_H
	self.paint = nil
	self.start_time = nil

	self.state = STATE_PLAYING
	self.needs_redraw = true
end

function Game:_update_playing()
	local changed = false

	if pd.buttonJustPressed(pd.kButtonB) and pd.buttonIsPressed(pd.kButtonA) then
		-- Both held: treat as a bail-out rather than a paint.
		self:_abandon()
		return
	end

	changed = self:_handle_cursor() or changed
	changed = self:_handle_paint() or changed

	if changed then
		self.start_time = self.start_time or pd.getCurrentTimeMilliseconds()
		self:_draw_playing()

		if self.puzzle:is_solved(self.player) then
			self:_complete()
			return
		end
	elseif self.needs_redraw then
		self:_draw_playing()
		self.needs_redraw = false
	end
end

function Game:_handle_cursor()
	-- The cursor is frozen while a run is being painted; the crank owns the
	-- gesture at that point and moving the anchor would be incoherent.
	if self.paint then
		return false
	end

	local dx, dy = 0, 0
	if self:_repeats(pd.kButtonLeft) then
		dx, self.axis = -1, AXIS_H
	elseif self:_repeats(pd.kButtonRight) then
		dx, self.axis = 1, AXIS_H
	elseif self:_repeats(pd.kButtonUp) then
		dy, self.axis = -1, AXIS_V
	elseif self:_repeats(pd.kButtonDown) then
		dy, self.axis = 1, AXIS_V
	else
		return false
	end

	self.cursor_x = math.max(1, math.min(self.puzzle.width, self.cursor_x + dx))
	self.cursor_y = math.max(1, math.min(self.puzzle.height, self.cursor_y + dy))
	return true
end

-- Tap A or B to toggle one cell. Hold and crank to extend the mark into a run
-- along the axis of the last d-pad movement -- which is how nonograms are
-- actually solved: deduce "a run of four", then draw four.
function Game:_handle_paint()
	if pd.buttonJustPressed(pd.kButtonA) then
		self:_begin_paint(FILLED)
		return true
	elseif pd.buttonJustPressed(pd.kButtonB) then
		self:_begin_paint(CROSSED)
		return true
	end

	if not self.paint then
		return false
	end

	if not pd.buttonIsPressed(self.paint.button) then
		self.paint = nil
		return false
	end

	local paint = self.paint
	paint.crank += pd.getCrankChange()

	local changed = false
	while paint.crank >= DEGREES_PER_CELL do
		paint.crank -= DEGREES_PER_CELL
		changed = self:_extend_run(1) or changed
	end
	while paint.crank <= -DEGREES_PER_CELL do
		paint.crank += DEGREES_PER_CELL
		changed = self:_extend_run(-1) or changed
	end

	return changed
end

function Game:_begin_paint(target)
	local index = self.puzzle:index(self.cursor_x, self.cursor_y)
	local current = self.player[index]
	local value = current == target and EMPTY or target

	self.paint = {
		anchor_x = self.cursor_x,
		anchor_y = self.cursor_y,
		value = value,
		-- Remember which button opened the gesture rather than inferring it
		-- from the value: an erase sets value to EMPTY, which on its own
		-- can't tell A from B.
		button = target == FILLED and pd.kButtonA or pd.kButtonB,
		offset = 0,
		crank = 0,
		snapshot = table.create(#self.player, 0),
	}

	for i = 1, #self.player do
		self.paint.snapshot[i] = self.player[i]
	end

	self:_apply_run()
	return true
end

function Game:_extend_run(delta)
	local paint = self.paint
	local limit
	if self.axis == AXIS_H then
		limit = delta > 0 and (self.puzzle.width - paint.anchor_x) or (1 - paint.anchor_x)
	else
		limit = delta > 0 and (self.puzzle.height - paint.anchor_y) or (1 - paint.anchor_y)
	end

	local next_offset = paint.offset + delta
	if delta > 0 and next_offset > limit then
		return false
	elseif delta < 0 and next_offset < limit then
		return false
	end

	paint.offset = next_offset
	self:_apply_run()
	return true
end

-- Repaint from the snapshot every time so shrinking a run cleanly un-paints
-- the cells it no longer covers.
function Game:_apply_run()
	local paint = self.paint
	for i = 1, #self.player do
		self.player[i] = paint.snapshot[i]
	end

	local step = paint.offset >= 0 and 1 or -1
	for i = 0, math.abs(paint.offset) do
		local x, y = paint.anchor_x, paint.anchor_y
		if self.axis == AXIS_H then
			x += i * step
		else
			y += i * step
		end
		self.player[self.puzzle:index(x, y)] = paint.value
	end

	self.cursor_x = paint.anchor_x
	self.cursor_y = paint.anchor_y
	if self.axis == AXIS_H then
		self.cursor_x = paint.anchor_x + paint.offset
	else
		self.cursor_y = paint.anchor_y + paint.offset
	end

	self:_auto_cross()
end

-- Once a line's filled runs match its clues, the remaining cells can only be
-- empty -- crossing them saves the player a lot of bookkeeping.
function Game:_auto_cross()
	local puzzle = self.puzzle

	for y = 1, puzzle.height do
		if self.numbers:is_row_complete(self.player, y) then
			for x = 1, puzzle.width do
				local i = puzzle:index(x, y)
				if self.player[i] == EMPTY then
					self.player[i] = CROSSED
				end
			end
		end
	end

	for x = 1, puzzle.width do
		if self.numbers:is_column_complete(self.player, x) then
			for y = 1, puzzle.height do
				local i = puzzle:index(x, y)
				if self.player[i] == EMPTY then
					self.player[i] = CROSSED
				end
			end
		end
	end
end

function Game:_draw_playing()
	gfx.clear()
	self.board:draw(self.player, self.cursor_x, self.cursor_y)

	gfx.setFont(gfx.getSystemFont())
	gfx.drawText(self.puzzle.pack, 6, 4)

	if self.start_time then
		local elapsed = pd.getCurrentTimeMilliseconds() - self.start_time
		local text = Progress.format_time(elapsed)
		local w = gfx.getTextSize(text)
		gfx.drawText(text, 400 - w - 6, 4)
	end

	gfx.drawText("A+B: quit", 6, 222)
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
