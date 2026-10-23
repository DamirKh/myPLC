local config = require("modules.config")
local sensor_manager = require("modules.sensor_manager")

local function make_manager()
   local cfg = config.defaults()
   config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF00", "room", "room 1", 0)
   config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF01", "room", "room 2", 0)
   config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF02", "floor", "floor 1", 0)
   config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF03", "floor", "floor 2", 0)
   config.set_sensor(cfg, "diag", "28AABBCCDDEEFF10", "supply", "supply 1", 0)
   config.set_sensor(cfg, "diag", "28AABBCCDDEEFF11", "supply", "supply 2", 0)
   config.set_sensor(cfg, "diag", "28AABBCCDDEEFF12", "return", "return 1", 0)
   return sensor_manager.new(cfg)
end

return function(t)
   t.test("snapshot aggregates duplicate roles", function()
      local manager = make_manager()
      local now = 1000
      manager.last["control_a:28AABBCCDDEEFF00"] = { ok = true, temp = 20, ts = now }
      manager.last["control_a:28AABBCCDDEEFF01"] = { ok = true, temp = 22, ts = now }
      manager.last["control_a:28AABBCCDDEEFF02"] = { ok = true, temp = 26, ts = now }
      manager.last["control_a:28AABBCCDDEEFF03"] = { ok = true, temp = 28, ts = now }
      manager.last["diag:28AABBCCDDEEFF10"] = { ok = true, temp = 30, ts = now }
      manager.last["diag:28AABBCCDDEEFF11"] = { ok = true, temp = 34, ts = now }
      manager.last["diag:28AABBCCDDEEFF12"] = { ok = true, temp = 24, ts = now }

      local snap = manager:snapshot(now)
      t.assert_near(snap.actual.room, 21, 0.0001)
      t.assert_near(snap.actual.floor, 28, 0.0001)
      t.assert_near(snap.actual.supply, 32, 0.0001)
      t.assert_near(snap.actual.return_temp, 24, 0.0001)
      t.assert_eq(#snap.diagnostics, 7)
   end)

   t.test("snapshot excludes stale sensors from aggregates", function()
      local manager = make_manager()
      local now = 1000
      manager.last["control_a:28AABBCCDDEEFF00"] = { ok = true, temp = 20, ts = now }
      manager.last["control_a:28AABBCCDDEEFF01"] = { ok = true, temp = 40, ts = now - 100 }
      manager.last["control_a:28AABBCCDDEEFF02"] = { ok = true, temp = 26, ts = now }
      manager.last["diag:28AABBCCDDEEFF10"] = { ok = true, temp = 30, ts = now }
      manager.last["diag:28AABBCCDDEEFF11"] = { ok = true, temp = 50, ts = now - 100 }

      local snap = manager:snapshot(now)
      t.assert_near(snap.actual.room, 20, 0.0001)
      t.assert_near(snap.actual.supply, 30, 0.0001)
      t.assert_eq(#snap.rooms, 1)
      t.assert_eq(#snap.water, 1)
   end)

   t.test("successive reads expose temperature delta", function()
      local manager = make_manager()
      local item = {
         key = "control_a:28AABBCCDDEEFF00",
         sensor = manager.cfg.sensors["control_a:28AABBCCDDEEFF00"],
      }
      manager:set_ok(item, { temp = 21, raw = 336 }, 1000)
      manager:set_ok(item, { temp = 21.5, raw = 344 }, 1010)
      local snap = manager:snapshot(1010)
      local found
      for _, diagnostic in ipairs(snap.diagnostics) do
         if diagnostic.key == item.key then
            found = diagnostic
         end
      end
      t.assert_true(found)
      t.assert_near(found.delta, 0.5, 0.0001)
   end)

   t.test("snapshot returns nil aggregates without valid sensors", function()
      local manager = make_manager()
      local snap = manager:snapshot(1000)
      t.assert_eq(snap.actual.room, nil)
      t.assert_eq(snap.actual.floor, nil)
      t.assert_eq(snap.actual.supply, nil)
      t.assert_eq(snap.actual.return_temp, nil)
   end)
end
