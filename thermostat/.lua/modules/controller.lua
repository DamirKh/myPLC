local M = {}

local function max_value(t)
   local v = t[1]
   for i = 2, #t do
      if t[i] > v then
         v = t[i]
      end
   end
   return v
end

local function min_value(t)
   local v = t[1]
   for i = 2, #t do
      if t[i] < v then
         v = t[i]
      end
   end
   return v
end

local function copy_array(t)
   local out = {}
   for i = 1, #(t or {}) do
      out[i] = t[i]
   end
   return out
end

function M.new(cfg, now)
   now = now or 0
   return {
      pump = false,
      mode = "auto",
      target = cfg.control.target_room,
      last_on = nil,
      last_off = now,
      last_change = now,
      last_reason = "init",
      last_exercise = 0,
      exercise_until = nil,
      faults = {},
      warnings = {},
   }
end

function M.step(state, inputs, cfg, now)
   inputs = inputs or {}
   local c = cfg.control
   local s = {}
   for k, v in pairs(state) do
      s[k] = v
   end
   s.faults = copy_array(inputs.faults)
   s.warnings = copy_array(inputs.warnings)
   s.mode = inputs.mode or s.mode or "auto"
   s.target = inputs.override_target or inputs.schedule_target or c.target_room

   local rooms = inputs.rooms or {}
   local floors = inputs.floors or {}
   local water = inputs.water or {}

   local safety = false
   local want_on = false
   local reason = "idle"

   if inputs.force_off then
      want_on = false
      reason = "service"
      safety = true
   elseif "off" == s.mode then
      want_on = false
      reason = "off"
      safety = true
   elseif #rooms == 0 or #floors == 0 then
      s.faults[#s.faults + 1] = (#rooms == 0) and "no_valid_room_sensor" or "no_valid_floor_sensor"
      want_on = false
      reason = "fault"
      safety = true
   elseif #s.faults > 0 then
      want_on = false
      reason = "fault"
      safety = true
   elseif "manual" == s.mode then
      want_on = inputs.manual_pump and true or false
      reason = "manual"
      safety = true
   else
      local max_room = max_value(rooms)
      local min_room = min_value(rooms)
      local max_floor = max_value(floors)

      if max_floor >= c.floor_limit then
         want_on = false
         reason = "floor_limit"
         safety = true
      elseif c.frost_enabled then
         local coldest = nil
         for _, v in ipairs(water) do
            coldest = (not coldest or v < coldest) and v or coldest
         end
         for _, v in ipairs(floors) do
            coldest = (not coldest or v < coldest) and v or coldest
         end
         if coldest and coldest <= c.frost_threshold then
            want_on = true
            reason = "frost"
            safety = true
         end
      end

      if "idle" == reason then
         if s.pump then
            if min_room >= s.target + c.room_hysteresis then
               want_on = false
               reason = "room_reached"
            elseif max_floor >= c.floor_limit then
               want_on = false
               reason = "floor_limit"
               safety = true
            else
               want_on = true
               reason = "heating"
            end
         else
            local room_ok = max_room < (s.target - c.room_hysteresis)
            local floor_ok = max_floor < (c.floor_limit - c.floor_hysteresis)
            if room_ok and floor_ok then
               want_on = true
               reason = "demand"
            else
               want_on = false
               reason = "idle"
            end
         end
      end
   end

   local exercise = false
   if "auto" == s.mode and not safety and #s.faults == 0 then
      if s.exercise_until and now < s.exercise_until then
         want_on = true
         reason = "exercise"
         exercise = true
      elseif not s.pump and not want_on and c.pump_exercise_hours > 0 then
         local off_for = now - (s.last_off or now)
         local since_exercise = now - (s.last_exercise or 0)
         if off_for >= c.pump_exercise_hours * 3600 and since_exercise >= c.pump_exercise_hours * 3600 then
            want_on = true
            reason = "exercise"
            exercise = true
            s.exercise_until = now + c.pump_exercise_sec
            s.last_exercise = now
         end
      end
   end

   if not exercise then
      if want_on and not s.pump and "auto" == s.mode and not safety then
         if now - (s.last_off or now) < c.min_off_sec then
            want_on = false
            reason = "min_off"
         end
      elseif not want_on and s.pump and "auto" == s.mode and not safety then
         if now - (s.last_on or now) < c.min_on_sec then
            want_on = true
            reason = "min_on"
         end
      end
   end

   if s.exercise_until and now >= s.exercise_until then
      s.exercise_until = nil
      if s.pump then
         want_on = false
         reason = "exercise_done"
      end
   end

   if want_on ~= s.pump then
      s.pump = want_on
      s.last_change = now
      if want_on then
         s.last_on = now
      else
         s.last_off = now
      end
   end

   s.last_reason = reason
   return s
end

return M
