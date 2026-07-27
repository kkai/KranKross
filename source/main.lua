import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/timer"

import "constants"
import "puzzles"
import "model/puzzle"
import "model/numbers"
import "model/progress"
import "ui/board"
import "game"

local pd <const> = playdate

local game = Game()

function pd.update()
	game:update()
	pd.timer.updateTimers()
end
