local M = {}

function M.format_offset(minutes)
   minutes = tonumber(minutes) or 0
   local sign = minutes < 0 and "-" or "+"
   local abs_minutes = math.abs(minutes)
   return string.format("%s%02d:%02d", sign, math.floor(abs_minutes / 60), abs_minutes % 60)
end

function M.parse_offset(text)
   local sign, hours, minutes = tostring(text or ""):match("^([+-])(%d%d):(%d%d)$")
   if not sign then
      return nil
   end
   hours, minutes = tonumber(hours), tonumber(minutes)
   if not hours or not minutes or minutes % 30 ~= 0 then
      return nil
   end
   if hours > 14 or (14 == hours and minutes > 0) then
      return nil
   end
   local total = hours * 60 + minutes
   if "-" == sign then
      total = -total
   end
   if total < -720 or total > 840 then
      return nil
   end
   return total
end

function M.offset_from_parts(hours, minutes)
   hours = tonumber(hours)
   minutes = tonumber(minutes)
   if not hours or not minutes then
      return nil
   end
   if hours ~= math.floor(hours) or minutes ~= math.floor(minutes) then
      return nil
   end
   if hours < -12 or hours > 14 then
      return nil
   end
   if minutes < -30 or minutes > 30 or 0 ~= minutes % 30 then
      return nil
   end
   local total
   if 0 == hours then
      total = minutes
   else
      local sign = hours < 0 and -1 or 1
      total = hours * 60 + sign * math.abs(minutes)
   end
   if total < -720 or total > 840 then
      return nil
   end
   return total
end

function M.round_offset(minutes)
   minutes = tonumber(minutes) or 0
   return math.max(-720, math.min(840, math.floor((minutes + 15) / 30) * 30))
end

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
