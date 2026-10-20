local M = {}

local BLACK = { 0, 0, 0 }
local RED = { 255, 0, 0 }
local BLUE = { 0, 0, 255 }
local GREEN = { 0, 255, 0 }
local GREEN_DIM = { 0, 28, 0 }
local YELLOW = { 255, 180, 0 }
local WHITE = { 255, 255, 255 }

M.SLOT_TICKS = 12
M.GAP_TICKS = 4

local function slots(state)
   local list = {}
   if state.fault then
      list[#list + 1] = RED
   end
   if not state.wifi then
      list[#list + 1] = BLUE
   end
   if state.service then
      list[#list + 1] = YELLOW
   end
   list[#list + 1] = state.pump and GREEN or GREEN_DIM
   return list
end

function M.frame(state, tick)
   state = state or {}
   if state.boot then
      return WHITE
   end

   local list = slots(state)
   local width = M.SLOT_TICKS + M.GAP_TICKS
   local position = math.max(0, math.floor(tonumber(tick) or 0))
   local index = math.floor(position / width) % #list + 1
   if position % width >= M.SLOT_TICKS then
      return BLACK
   end
   return list[index]
end

return M
