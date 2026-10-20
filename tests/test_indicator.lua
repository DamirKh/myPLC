local indicator = require("modules.indicator")

local SLOT = indicator.SLOT_TICKS
local GAP = indicator.GAP_TICKS

local function eq(a, b)
   return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

return function(t)
   t.test("boot is white", function()
      t.assert_true(eq(indicator.frame({ boot = true }, 0), { 255, 255, 255 }))
      t.assert_true(eq(indicator.frame({ boot = true }, 100), { 255, 255, 255 }))
   end)

   t.test("normal pump on blinks bright green with a gap", function()
      local state = { wifi = true, pump = true }
      t.assert_true(eq(indicator.frame(state, 0), { 0, 255, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT - 1), { 0, 255, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT), { 0, 0, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT + GAP - 1), { 0, 0, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT + GAP), { 0, 255, 0 }))
   end)

   t.test("normal pump off blinks dim green", function()
      local state = { wifi = true, pump = false }
      t.assert_true(eq(indicator.frame(state, 0), { 0, 28, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT), { 0, 0, 0 }))
   end)

   t.test("fault slot is followed by pump slot", function()
      local state = { wifi = true, pump = false, fault = true }
      t.assert_true(eq(indicator.frame(state, 0), { 255, 0, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT), { 0, 0, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT + GAP), { 0, 28, 0 }))
      t.assert_true(eq(indicator.frame(state, 2 * (SLOT + GAP)), { 255, 0, 0 }))
   end)

   t.test("wifi down slot is followed by pump slot", function()
      local state = { wifi = false, pump = true }
      t.assert_true(eq(indicator.frame(state, 0), { 0, 0, 255 }))
      t.assert_true(eq(indicator.frame(state, SLOT + GAP), { 0, 255, 0 }))
   end)

   t.test("STA mode without connection shows blue", function()
      local state = { wifi_mode = "sta", wifi_sta_connected = false, pump = false }
      t.assert_true(eq(indicator.frame(state, 0), { 0, 0, 255 }))
   end)

   t.test("AP warning order is fault, purple, service, pump", function()
      local state = {
         wifi_mode = "ap", wifi_sta_connected = false, wifi_ap_client_active = false,
         pump = true, fault = true, service = true,
      }
      local width = SLOT + GAP
      t.assert_true(eq(indicator.frame(state, 0), { 255, 0, 0 }))
      t.assert_true(eq(indicator.frame(state, width), { 255, 0, 255 }))
      t.assert_true(eq(indicator.frame(state, 2 * width), { 255, 180, 0 }))
      t.assert_true(eq(indicator.frame(state, 3 * width), { 0, 255, 0 }))
   end)

   t.test("AP with an active web client has no purple slot", function()
      local state = { wifi_mode = "ap", wifi_ap_client_active = true, pump = true }
      t.assert_true(eq(indicator.frame(state, 0), { 0, 255, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT + GAP), { 0, 255, 0 }))
   end)

   t.test("service slot is followed by pump slot", function()
      local state = { wifi = true, pump = false, service = true }
      t.assert_true(eq(indicator.frame(state, 0), { 255, 180, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT + GAP), { 0, 28, 0 }))
   end)

   t.test("all active slots keep the agreed order", function()
      local state = { wifi = false, pump = true, service = true, fault = true }
      local width = SLOT + GAP
      t.assert_true(eq(indicator.frame(state, 0), { 255, 0, 0 }))
      t.assert_true(eq(indicator.frame(state, width), { 0, 0, 255 }))
      t.assert_true(eq(indicator.frame(state, 2 * width), { 255, 180, 0 }))
      t.assert_true(eq(indicator.frame(state, 3 * width), { 0, 255, 0 }))
      t.assert_true(eq(indicator.frame(state, 4 * width), { 255, 0, 0 }))
      t.assert_true(eq(indicator.frame(state, SLOT), { 0, 0, 0 }))
      t.assert_true(eq(indicator.frame(state, 3 * width + SLOT), { 0, 0, 0 }))
   end)

   t.test("inactive colors are absent from the cycle", function()
      local state = { wifi = true, pump = false }
      for tick = 0, 2 * (SLOT + GAP) - 1 do
         local color = indicator.frame(state, tick)
         t.assert_false(eq(color, { 255, 0, 0 }))
         t.assert_false(eq(color, { 0, 0, 255 }))
         t.assert_false(eq(color, { 255, 180, 0 }))
      end
   end)
end
