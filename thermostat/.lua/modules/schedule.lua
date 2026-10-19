local M = {}

function M.localtime(epoch, offset_minutes)
   return os.date("!*t", epoch + (offset_minutes or 0) * 60)
end

function M.weekday_monday(t)
   return ((t.wday + 5) % 7) + 1
end

function M.parse_hhmm(text)
   local h, m = tostring(text):match("^(%d%d?):(%d%d)$")
   if not h then
      return nil
   end
   h, m = tonumber(h), tonumber(m)
   if h > 23 or m > 59 then
      return nil
   end
   return h * 60 + m
end

local function contains(list, value)
   for _, v in ipairs(list) do
      if v == value then
         return true
      end
   end
   return false
end

function M.target_at(schedule, epoch)
   if not schedule or not schedule.enabled then
      return nil
   end
   local t = M.localtime(epoch, schedule.utc_offset_minutes or 0)
   local minute = t.hour * 60 + t.min
   local day = M.weekday_monday(t)
   local target = nil

   for _, block in ipairs(schedule.blocks or {}) do
      local start_min = M.parse_hhmm(block.start)
      local end_min = M.parse_hhmm(block.stop or block["end"])
      local days = block.days or { 1, 2, 3, 4, 5, 6, 7 }
      local active = false
      if start_min and end_min then
         if start_min <= end_min then
            active = contains(days, day) and minute >= start_min and minute < end_min
         else
            local previous_day = ((day - 2) % 7) + 1
            active = (contains(days, day) and minute >= start_min)
               or (contains(days, previous_day) and minute < end_min)
         end
      end
      if active and tonumber(block.target) then
         target = tonumber(block.target)
      end
   end

   return target
end

function M.effective_target(schedule, override, epoch)
   if override and override.target and override.expires and epoch < override.expires then
      return override.target, "override"
   end
   local target = M.target_at(schedule, epoch)
   if target then
      return target, "schedule"
   end
   return nil, "none"
end

function M.set_override(target, expires_epoch)
   return { target = tonumber(target), expires = tonumber(expires_epoch) }
end

return M
