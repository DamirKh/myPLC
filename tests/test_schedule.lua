local schedule = require("modules.schedule")

local function thursday_schedule()
   return {
      enabled = true,
      utc_offset_minutes = 0,
      blocks = {
         { days = { 4 }, start = "11:00", stop = "13:00", target = 23 },
      },
   }
end

return function(t)
   t.test("weekday monday mapping", function()
      local day = schedule.weekday_monday({ wday = 5 })
      t.assert_eq(day, 4)
   end)

   t.test("block target inside window", function()
      local target = schedule.target_at(thursday_schedule(), 12 * 3600)
      t.assert_eq(target, 23)
   end)

   t.test("block target outside window", function()
      local target = schedule.target_at(thursday_schedule(), 14 * 3600)
      t.assert_eq(target, nil)
   end)

   t.test("disabled schedule returns nil", function()
      local s = thursday_schedule()
      s.enabled = false
      t.assert_eq(schedule.target_at(s, 12 * 3600), nil)
   end)

   t.test("cross midnight block", function()
      local s = {
         enabled = true,
         utc_offset_minutes = 0,
         blocks = {
            { days = { 4 }, start = "22:00", stop = "06:00", target = 21 },
         },
      }
      t.assert_eq(schedule.target_at(s, 23 * 3600), 21)
      t.assert_eq(schedule.target_at(s, 29 * 3600), 21)
      t.assert_eq(schedule.target_at(s, 30 * 3600), nil)
   end)

   t.test("UTC offset formats as hours and minutes", function()
      t.assert_eq(schedule.format_offset(180), "+03:00")
      t.assert_eq(schedule.format_offset(-330), "-05:30")
      t.assert_eq(schedule.format_offset(0), "+00:00")
   end)

   t.test("UTC offset parses 30-minute steps", function()
      t.assert_eq(schedule.parse_offset("+03:00"), 180)
      t.assert_eq(schedule.parse_offset("-05:30"), -330)
      t.assert_eq(schedule.parse_offset("+14:00"), 840)
      t.assert_eq(schedule.parse_offset("-12:00"), -720)
      t.assert_eq(schedule.parse_offset("+03:15"), nil)
      t.assert_eq(schedule.parse_offset("+15:00"), nil)
      t.assert_eq(schedule.parse_offset("3:00"), nil)
   end)

   t.test("UTC offset rounds to 30 minutes", function()
      t.assert_eq(schedule.round_offset(190), 180)
      t.assert_eq(schedule.round_offset(200), 210)
      t.assert_eq(schedule.round_offset(-40), -30)
   end)

   t.test("override has priority while active", function()
      local s = thursday_schedule()
      local override = { target = 25, expires = 12 * 3600 + 600 }
      local target, source = schedule.effective_target(s, override, 12 * 3600)
      t.assert_eq(target, 25)
      t.assert_eq(source, "override")
      target, source = schedule.effective_target(s, override, 12 * 3600 + 601)
      t.assert_eq(target, 23)
      t.assert_eq(source, "schedule")
   end)
end
