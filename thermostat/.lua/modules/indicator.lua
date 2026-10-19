local M = {}

local BLACK = { 0, 0, 0 }
local RED = { 255, 0, 0 }
local BLUE = { 0, 0, 255 }
local GREEN = { 0, 255, 0 }
local GREEN_DIM = { 0, 28, 0 }
local YELLOW = { 255, 180, 0 }
local WHITE = { 255, 255, 255 }

local HEARTBEAT_BOOST = 4

local function color(r, g, b, boost)
   return { r, g, b, boost or 1 }
end

local function with_boost(c, boost)
   return color(c[1], c[2], c[3], boost)
end

local function base_color(state)
   if state.boot then
      return WHITE
   end
   if state.fault then
      return RED
   end
   if state.service then
      return YELLOW
   end
   if not state.wifi then
      return BLUE
   end
   if state.pump then
      return GREEN
   end
   return GREEN_DIM
end

function M.color(state, blink_on, heartbeat_on)
   state = state or {}
   local base = base_color(state)
   local blinking = not state.boot and (state.fault or state.service or not state.wifi)

   if heartbeat_on then
      return with_boost(base, HEARTBEAT_BOOST)
   end
   if blinking and not blink_on then
      return color(BLACK[1], BLACK[2], BLACK[3], 1)
   end
   return with_boost(base, 1)
end

return M
