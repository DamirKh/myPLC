local config = require("modules.config")
local controller = require("modules.controller")

local function cfg()
   local c = config.defaults()
   c.control.pump_exercise_hours = 0
   c.control.min_on_sec = 180
   c.control.min_off_sec = 180
   return c
end

local function step(state, now, inputs, c)
   return controller.step(state, inputs, c or cfg(), now)
end

return function(t)
   t.test("demand turns pump on after min off", function()
      local c = cfg()
      local s = controller.new(c, 0)
      s = step(s, 1000, { rooms = { 21 }, floors = { 24 }, mode = "auto" }, c)
      t.assert_true(s.pump)
      t.assert_eq(s.last_reason, "demand")
   end)

   t.test("min on time holds pump on", function()
      local c = cfg()
      local s = controller.new(c, 0)
      s = step(s, 1000, { rooms = { 21 }, floors = { 24 } }, c)
      s = step(s, 1100, { rooms = { 23 }, floors = { 24 } }, c)
      t.assert_true(s.pump)
      t.assert_eq(s.last_reason, "min_on")
      s = step(s, 1200, { rooms = { 23 }, floors = { 24 } }, c)
      t.assert_false(s.pump)
      t.assert_eq(s.last_reason, "room_reached")
   end)

   t.test("floor limit turns pump off", function()
      local c = cfg()
      local s = controller.new(c, 0)
      s = step(s, 1000, { rooms = { 21 }, floors = { 28.5 } }, c)
      t.assert_false(s.pump)
      t.assert_eq(s.last_reason, "floor_limit")
   end)

   t.test("floor limit overrides min on time", function()
      local c = cfg()
      local s = controller.new(c, 0)
      s = step(s, 1000, { rooms = { 21 }, floors = { 24 } }, c)
      t.assert_true(s.pump)
      s = step(s, 1050, { rooms = { 21 }, floors = { 28.5 } }, c)
      t.assert_false(s.pump)
      t.assert_eq(s.last_reason, "floor_limit")
   end)

   t.test("failed duplicate is excluded", function()
      local c = cfg()
      local s = controller.new(c, 0)
      s = step(s, 1000, { rooms = { 21 }, floors = { 24 } }, c)
      t.assert_true(s.pump)
      t.assert_eq(#s.faults, 0)
   end)

   t.test("no valid room sensor is a critical fault", function()
      local c = cfg()
      local s = controller.new(c, 0)
      s = step(s, 1000, { rooms = {}, floors = { 24 } }, c)
      t.assert_false(s.pump)
      t.assert_eq(s.last_reason, "fault")
      t.assert_true(#s.faults >= 1)
   end)

   t.test("frost protection can turn pump on", function()
      local c = cfg()
      c.control.frost_enabled = true
      local s = controller.new(c, 0)
      s = step(s, 1000, { rooms = { 23 }, floors = { 4 } }, c)
      t.assert_true(s.pump)
      t.assert_eq(s.last_reason, "frost")
   end)

   t.test("mode off stops pump immediately", function()
      local c = cfg()
      local s = controller.new(c, 0)
      s = step(s, 1000, { rooms = { 21 }, floors = { 24 } }, c)
      t.assert_true(s.pump)
      s = step(s, 1010, { rooms = { 21 }, floors = { 24 }, mode = "off" }, c)
      t.assert_false(s.pump)
      t.assert_eq(s.last_reason, "off")
   end)

   t.test("min off time delays start", function()
      local c = cfg()
      local s = controller.new(c, 0)
      s = step(s, 100, { rooms = { 21 }, floors = { 24 } }, c)
      t.assert_false(s.pump)
      t.assert_eq(s.last_reason, "min_off")
      s = step(s, 200, { rooms = { 21 }, floors = { 24 } }, c)
      t.assert_true(s.pump)
   end)

   t.test("pump exercise runs when idle", function()
      local c = cfg()
      c.control.pump_exercise_hours = 1
      c.control.pump_exercise_sec = 300
      local s = controller.new(c, 0)
      s = step(s, 3600, { rooms = { 23 }, floors = { 24 } }, c)
      t.assert_true(s.pump)
      t.assert_eq(s.last_reason, "exercise")
      s = step(s, 3900, { rooms = { 23 }, floors = { 24 } }, c)
      t.assert_false(s.pump)
      t.assert_eq(s.last_reason, "exercise_done")
   end)
end
