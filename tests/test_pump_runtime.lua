local pump_runtime = require("modules.pump_runtime")

return function(t)
   t.test("counts only intervals that were running", function()
      local runtime = pump_runtime.new(10)
      runtime:update(1000, false)
      runtime:update(61000, true)
      t.assert_near(runtime.seconds, 10, 0.0001)

      runtime:update(121000, true)
      t.assert_near(runtime.seconds, 70, 0.0001)

      runtime:update(181000, false)
      t.assert_near(runtime.seconds, 130, 0.0001)

      runtime:update(241000, false)
      t.assert_near(runtime.seconds, 130, 0.0001)
      t.assert_near(runtime:hours(), 130 / 3600, 0.00001)
   end)

   t.test("ignores a backwards clock", function()
      local runtime = pump_runtime.new(5)
      runtime:update(10000, true)
      runtime:update(9000, true)
      t.assert_near(runtime.seconds, 5, 0.0001)
   end)

   t.test("reset clears accumulated time", function()
      local runtime = pump_runtime.new(123)
      runtime:reset()
      t.assert_eq(runtime.seconds, 0)
   end)
end
