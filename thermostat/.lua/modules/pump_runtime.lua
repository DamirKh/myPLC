local M = {}
M.__index = M

function M.new(seconds)
   seconds = tonumber(seconds) or 0
   if seconds < 0 then
      seconds = 0
   end
   return setmetatable({
      seconds = seconds,
      last_ms = nil,
      running = false,
   }, M)
end

function M:update(now_ms, running)
   now_ms = tonumber(now_ms)
   if not now_ms then
      return
   end
   if self.last_ms and now_ms > self.last_ms and self.running then
      self.seconds = self.seconds + (now_ms - self.last_ms) / 1000
   end
   self.last_ms = now_ms
   self.running = running and true or false
end

function M:reset()
   self.seconds = 0
end

function M:hours()
   return self.seconds / 3600
end

return M
