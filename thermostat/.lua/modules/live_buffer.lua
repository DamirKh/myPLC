local M = {}
M.__index = M

local DEFAULT_WINDOW_SEC = 600
local DEFAULT_MAX_POINTS = 1200

local function trim(points, cutoff, max_points)
   local first = 1
   while first <= #points and points[first].t < cutoff do
      first = first + 1
   end
   if first > 1 then
      local count = #points - first + 1
      for i = 1, count do
         points[i] = points[first + i - 1]
      end
      for i = count + 1, #points do
         points[i] = nil
      end
   end
   while #points > max_points do
      table.remove(points, 1)
   end
end

function M.new(window_sec, max_points)
   return setmetatable({
      window_sec = math.max(1, math.floor(tonumber(window_sec) or DEFAULT_WINDOW_SEC)),
      max_points = math.max(2, math.floor(tonumber(max_points) or DEFAULT_MAX_POINTS)),
      series = {},
   }, M)
end

function M:add(key, t, value)
   if "string" ~= type(key) or "number" ~= type(t) or "number" ~= type(value) then
      return
   end
   if value ~= value then
      return
   end
   local points = self.series[key]
   if not points then
      points = {}
      self.series[key] = points
   end
   local last = points[#points]
   if last and last.t == t then
      last.v = value
   else
      points[#points + 1] = { t = t, v = value }
   end
   trim(points, t - self.window_sec, self.max_points)
end

function M:prune(now)
   local cutoff = now - self.window_sec
   for key, points in pairs(self.series) do
      trim(points, cutoff, self.max_points)
      if 0 == #points then
         self.series[key] = nil
      end
   end
end

function M:record(snapshot, now)
   now = tonumber(now) or os.time()
   self:prune(now)
   for _, item in ipairs(snapshot and snapshot.diagnostics or {}) do
      if item.ok and "number" == type(item.temp) then
         self:add(item.key, now, item.temp)
      end
   end
end

function M:list(now)
   now = tonumber(now) or os.time()
   self:prune(now)
   local out = {}
   for key, points in pairs(self.series) do
      local copy = {}
      for i, point in ipairs(points) do
         copy[i] = { t = point.t, v = point.v }
      end
      out[key] = copy
   end
   return {
      window_sec = self.window_sec,
      series = out,
   }
end

return M
