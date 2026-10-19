local indicator = require("modules.indicator")

local function eq(a, b)
   return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

return function(t)
   t.test("fault blinks red", function()
      t.assert_true(eq(indicator.color({ fault = true }, true), { 255, 0, 0 }))
      t.assert_true(eq(indicator.color({ fault = true }, false), { 0, 0, 0 }))
   end)

   t.test("wifi down blinks blue", function()
      t.assert_true(eq(indicator.color({ wifi = false }, true), { 0, 0, 255 }))
      t.assert_true(eq(indicator.color({ wifi = false }, false), { 0, 0, 0 }))
   end)

   t.test("pump on is solid green", function()
      t.assert_true(eq(indicator.color({ wifi = true, pump = true }, false), { 0, 255, 0 }))
   end)

   t.test("idle is dim green", function()
      t.assert_true(eq(indicator.color({ wifi = true, pump = false }, false), { 0, 28, 0 }))
   end)

   t.test("service blinks yellow", function()
      t.assert_true(eq(indicator.color({ service = true }, true), { 255, 180, 0 }))
   end)

   t.test("boot is white", function()
      t.assert_true(eq(indicator.color({ boot = true }, false), { 255, 255, 255 }))
   end)

   t.test("fault has priority over wifi and pump", function()
      t.assert_true(eq(indicator.color({ fault = true, wifi = false, pump = true }, true), { 255, 0, 0 }))
   end)

   t.test("heartbeat boosts fault color even in blink-off phase", function()
      local c = indicator.color({ fault = true }, false, true)
      t.assert_true(eq(c, { 255, 0, 0 }))
      t.assert_eq(c[4], 4)
   end)

   t.test("heartbeat boosts idle dim green", function()
      local c = indicator.color({ wifi = true, pump = false }, false, true)
      t.assert_true(eq(c, { 0, 28, 0 }))
      t.assert_eq(c[4], 4)
   end)

   t.test("normal color has boost 1", function()
      t.assert_eq(indicator.color({ wifi = true, pump = true }, false, false)[4], 1)
   end)
end
