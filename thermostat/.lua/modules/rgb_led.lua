local M = {}

local Led = {}
Led.__index = Led

function M.available()
   return "table" == type(esp32) and "function" == type(esp32.rmttx)
end

function M.new(gpio, opts)
   if not M.available() then
      return nil, "esp32 RMT API is not available"
   end
   local o = opts or {}
   local self = setmetatable({
      gpio = gpio,
      brightness = math.max(0, math.min(1, tonumber(o.brightness) or 0.25)),
      last = nil,
   }, Led)
   local rmt, err = esp32.rmttx({
      gpio = gpio,
      resolution = 10000000,
   })
   if not rmt then
      return nil, err
   end
   self.rmt = rmt
   rmt:enable()
   return self
end

local function scale(value, brightness)
   value = math.floor(math.max(0, math.min(255, value)) * brightness)
   return value
end

function Led:write(r, g, b)
   if not self.rmt then
      return
   end
   r, g, b = scale(r, self.brightness), scale(g, self.brightness), scale(b, self.brightness)
   if self.last and self.last[1] == g and self.last[2] == r and self.last[3] == b then
      return
   end
   self.last = { g, r, b }
   local ok = pcall(function()
      self.rmt:transmit({}, {
         { true, { 1, 4, 0, 8 }, { 1, 8, 0, 4 }, { g, r, b } },
         { 0, 150, 0, 150 },
      })
   end)
   if not ok then
      self.last = nil
   end
end

function Led:off()
   self:write(0, 0, 0)
end

function Led:close()
   if self.rmt then
      pcall(function()
         self.rmt:close()
      end)
      self.rmt = nil
   end
end

return M
