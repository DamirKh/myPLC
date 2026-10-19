local M = {}

local Bus = {}
Bus.__index = Bus

local RESOLUTION = 10000000
local TICK = 10
local DEFAULT_TIMEOUT_MS = 250

function M.available()
   return "table" == type(esp32) and "function" == type(esp32.rmtrx) and "function" == type(esp32.rmttx)
end

function M.new(gpio, opts)
   if not M.available() then
      return nil, "esp32 RMT API is not available"
   end
   local o = opts or {}
   local self = setmetatable({}, Bus)
   self.gpio = gpio
   self.timeout_ms = o.timeout_ms or DEFAULT_TIMEOUT_MS
   self.waiting = false
   self.co = nil
   self.result = nil
   self.overflow = nil
   self.closed = false

   local rx, rxerr = esp32.rmtrx({
      gpio = gpio,
      resolution = RESOLUTION,
      callback = function(symbols, overflow)
         self:on_receive(symbols, overflow)
      end,
   })
   if not rx then
      return nil, rxerr
   end
   self.rx = rx

   local tx, txerr = esp32.rmttx({
      gpio = gpio,
      resolution = RESOLUTION,
      opendrain = true,
   }, rx)
   if not tx then
      rx:close()
      return nil, txerr
   end
   self.tx = tx
   tx:enable()
   return self
end

function Bus:on_receive(symbols, overflow)
   self.result = symbols
   self.overflow = overflow
   if not self.waiting then
      return
   end
   local co = self.co
   self.waiting = false
   if self.timer then
      self.timer:cancel()
      self.timer = nil
   end
   if co and "suspended" == coroutine.status(co) then
      coroutine.resume(co, symbols, overflow)
   end
end

function Bus:await()
   local co = coroutine.running()
   if not co then
      error("1-Wire bus must be used inside a coroutine")
   end
   if self.result then
      local symbols, overflow = self.result, self.overflow
      self.result, self.overflow = nil, nil
      return symbols, overflow
   end
   self.co = co
   self.waiting = true
   if ba and ba.timer then
      self.timer = ba.timer(function()
         if not self.waiting then
            return
         end
         self.waiting = false
         self.timer = nil
         local current = self.co
         if current and "suspended" == coroutine.status(current) then
            coroutine.resume(current, nil, "timeout")
         end
      end)
      self.timer:set(self.timeout_ms, true)
   end
   local symbols, overflow = coroutine.yield()
   self.waiting = false
   if self.timer then
      self.timer:cancel()
      self.timer = nil
   end
   if "timeout" == overflow then
      return nil, "timeout"
   end
   return symbols, overflow
end

function Bus:transfer(rx_cfg, symbols)
   if self.closed then
      return nil, "bus closed"
   end
   self.result, self.overflow = nil, nil
   self.rx:receive(rx_cfg)
   self.tx:transmit({ eot = 1 }, symbols)
   return self:await()
end

function Bus:reset()
   local symbols, err = self:transfer(
      { min = 2000, max = 480 * 2 * 1000, len = 64 },
      { { 0, 480 * TICK, 1, 70 * TICK } }
   )
   if not symbols then
      return nil, err
   end
   return #symbols >= 2, symbols
end

function Bus:write_byte(value)
   return self:write_byte_raw(value)
end

function Bus:write_byte_raw(value)
   local symbols, err = self:transfer(
      { min = 900, max = 70 * 1000, len = 32 },
      {
         {
            false,
            { 0, 60 * TICK, 1, 2 * TICK },
            { 0, 6 * TICK, 1, 56 * TICK },
            { value & 0xFF },
         },
      }
   )
   if not symbols then
      return nil, err
   end
   return symbols
end

local function decode_bytes(symbols)
   local out = {}
   local byte, mask = 0, 1
   for _, sym in ipairs(symbols or {}) do
      if sym[2] and sym[2] <= 15 then
         byte = byte | mask
      end
      mask = mask << 1
      if 256 == mask then
         out[#out + 1] = byte
         byte, mask = 0, 1
      end
   end
   return out
end

function Bus:read_byte()
   local symbols, err = self:write_byte_raw(0xFF)
   if not symbols then
      return nil, err
   end
   local bytes = decode_bytes(symbols)
   return bytes[1], bytes
end

function Bus:write_bit(bit)
   local symbol = bit and { 0, 6 * TICK, 1, 64 * TICK } or { 0, 60 * TICK, 1, 10 * TICK }
   local symbols, err = self:transfer(
      { min = 900, max = 120 * 1000, len = 8 },
      { symbol }
   )
   if not symbols then
      return nil, err
   end
   return true
end

function Bus:read_bit()
   local symbols, err = self:transfer(
      { min = 900, max = 120 * 1000, len = 8 },
      { { 0, 6 * TICK, 1, 64 * TICK } }
   )
   if not symbols then
      return nil, err
   end
   local first = symbols[1]
   if not first then
      return nil, "no symbol"
   end
   return first[2] <= 15
end

function Bus:close()
   if self.closed then
      return
   end
   self.closed = true
   if self.timer then
      self.timer:cancel()
      self.timer = nil
   end
   if self.tx then
      self.tx:close()
      self.tx = nil
   end
   if self.rx then
      self.rx:close()
      self.rx = nil
   end
end

return M
