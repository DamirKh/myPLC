local here = arg[0]:match("^(.*)/") or "."
package.path = table.concat({
   here .. "/../thermostat/.lua/?.lua",
   here .. "/../thermostat/.lua/?/init.lua",
   here .. "/?.lua",
   package.path,
}, ";")

local pass, fail = 0, 0
local current = ""

local ctx = {}

function ctx.test(name, fn)
   current = name
   local ok, err = pcall(fn)
   if ok then
      pass = pass + 1
      print("ok   - " .. name)
   else
      fail = fail + 1
      print("FAIL - " .. name .. ": " .. tostring(err))
   end
end

function ctx.assert_eq(actual, expected, message)
   if actual ~= expected then
      error((message or "assert_eq failed") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected), 2)
   end
end

function ctx.assert_near(actual, expected, tolerance, message)
   tolerance = tolerance or 0.0001
   if "number" ~= type(actual) or math.abs(actual - expected) > tolerance then
      error((message or "assert_near failed") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected), 2)
   end
end

function ctx.assert_true(value, message)
   if not value then
      error((message or "assert_true failed"), 2)
   end
end

function ctx.assert_false(value, message)
   if value then
      error((message or "assert_false failed"), 2)
   end
end

local files = {
   "test_ds18b20.lua",
   "test_config.lua",
   "test_sensor_manager.lua",
   "test_pump_runtime.lua",
   "test_controller.lua",
   "test_schedule.lua",
   "test_history.lua",
   "test_indicator.lua",
   "test_pin.lua",
   "test_mqtt.lua",
}

for _, file in ipairs(files) do
   local chunk, err = loadfile(here .. "/" .. file)
   if not chunk then
      error("cannot load " .. file .. ": " .. tostring(err))
   end
   local fn = chunk()
   fn(ctx)
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
   os.exit(1)
end
