local M = {}

local BLACK = { 0, 0, 0 }
local RED = { 255, 0, 0 }
local BLUE = { 0, 0, 255 }
local GREEN = { 0, 255, 0 }
local GREEN_DIM = { 0, 28, 0 }
local YELLOW = { 255, 180, 0 }
local WHITE = { 255, 255, 255 }

function M.color(state, blink_on)
   state = state or {}
   if state.boot then
      return WHITE
   end
   if state.fault then
      return blink_on and RED or BLACK
   end
   if state.service then
      return blink_on and YELLOW or BLACK
   end
   if not state.wifi then
      return blink_on and BLUE or BLACK
   end
   if state.pump then
      return GREEN
   end
   return GREEN_DIM
end

return M
