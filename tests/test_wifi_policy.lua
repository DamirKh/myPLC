local policy = require("modules.wifi_policy")

local function cfg(overrides)
   local out = {
      wifi = {
         mode = "auto",
         sta_ssid = "",
         sta_password_enc = "",
         sta_confirmed = false,
      },
   }
   for key, value in pairs(overrides or {}) do
      out.wifi[key] = value
   end
   return out
end

return function(t)
   t.test("unconfigured STA forces AP", function()
      local mode, reason = policy.desired(cfg(), false, false)
      t.assert_eq(mode, "ap")
      t.assert_eq(reason, "unconfigured")
   end)

   t.test("configured STA attempts connection", function()
      local c = cfg({ sta_ssid = "gft", sta_password_enc = "enc" })
      local mode, reason = policy.desired(c, false, false)
      t.assert_eq(mode, "sta")
      t.assert_eq(reason, "unconfirmed")
      t.assert_true(policy.sta_configured(c))
   end)

   t.test("confirmed STA wins without a jumper", function()
      local c = cfg({ sta_ssid = "gft", sta_password_enc = "enc", sta_confirmed = true })
      local mode, reason = policy.desired(c, false, false)
      t.assert_eq(mode, "sta")
      t.assert_eq(reason, "confirmed")
      t.assert_false(policy.should_fallback(c))
   end)

   t.test("unconfirmed STA falls back after timeout", function()
      local c = cfg({ sta_ssid = "gft", sta_password_enc = "enc" })
      t.assert_true(policy.should_fallback(c))
   end)

   t.test("jumper forces AP", function()
      local c = cfg({ sta_ssid = "gft", sta_password_enc = "enc", sta_confirmed = true })
      local mode, reason = policy.desired(c, true, false)
      t.assert_eq(mode, "ap")
      t.assert_eq(reason, "jumper")
   end)

   t.test("latched AP survives jumper removal", function()
      local c = cfg({ sta_ssid = "gft", sta_password_enc = "enc", sta_confirmed = true })
      local mode, reason = policy.desired(c, false, true)
      t.assert_eq(mode, "ap")
      t.assert_eq(reason, "jumper")
   end)

   t.test("manual AP is a persistent override", function()
      local c = cfg({ mode = "ap", sta_ssid = "gft", sta_password_enc = "enc", sta_confirmed = true })
      local mode, reason = policy.desired(c, false, false)
      t.assert_eq(mode, "ap")
      t.assert_eq(reason, "manual")
   end)

   t.test("partial credentials are not configured", function()
      t.assert_false(policy.sta_configured(cfg({ sta_ssid = "gft" })))
      t.assert_false(policy.sta_configured(cfg({ sta_password_enc = "enc" })))
   end)

   t.test("jumper level accepts booleans and numbers", function()
      t.assert_true(policy.jumper_closed(false))
      t.assert_false(policy.jumper_closed(true))
      t.assert_true(policy.jumper_closed(0))
      t.assert_false(policy.jumper_closed(1))
      t.assert_eq(policy.jumper_closed(nil), nil)
   end)
end
