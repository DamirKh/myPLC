local ds = require("modules.ds18b20")
local onewire = require("modules.onewire_rmt")
local M = {}
M.__index = M

local BUS_NAMES = { "diag", "control_a", "control_b" }

local function sleep(ms)
   if ba and ba.sleep then
      ba.sleep(ms)
   end
end

function M.new(cfg)
   return setmetatable({
      cfg = cfg,
      last = {},
      last_cycle = nil,
      scan_result = nil,
      discovered = {},
   }, M)
end

function M:open_bus(name)
   local pin = self.cfg.pins and self.cfg.pins[name]
   if not pin then
      return nil, "pin_missing"
   end
   local bus, err = onewire.new(pin)
   if not bus then
      return nil, err or "rmt_open_failed"
   end
   return bus
end

function M:read_one(bus, rom)
   local rom_bytes, err = ds.rom_from_string(rom)
   if not rom_bytes then
      return nil, err
   end
   local data, perr = ds.read_scratchpad(bus, rom_bytes)
   if not data then
      return nil, perr
   end
   if data.power_on_reset then
      return nil, "power_on_reset_85C"
   end
   return data
end

function M:set_ok(item, data, now)
   local prev = self.last[item.key]
   self.last[item.key] = {
      ok = true,
      temp = data.temp + (item.sensor.offset or 0),
      raw = data.raw,
      ts = now,
      good_count = (prev and prev.good_count or 0) + 1,
      fail_count = 0,
   }
end

function M:set_failure(item, err, now)
   local prev = self.last[item.key] or {}
   self.last[item.key] = {
      ok = false,
      err = err,
      ts = now,
      temp = prev.temp,
      good_count = 0,
      fail_count = (prev.fail_count or 0) + 1,
   }
end

local function group_by_bus(cfg)
   local map = {}
   for key, sensor in pairs(cfg.sensors or {}) do
      local list = map[sensor.bus]
      if not list then
         list = {}
         map[sensor.bus] = list
      end
      list[#list + 1] = { key = key, sensor = sensor }
   end
   return map
end

local function sensor_key(bus, rom)
   return bus .. ":" .. tostring(rom):upper()
end

function M:record(bus, rom, data, err, now)
   local key = sensor_key(bus, rom)
   local sensor = self.cfg.sensors and self.cfg.sensors[key] or { offset = 0 }
   local item = { key = key, sensor = sensor }
   if data then
      self:set_ok(item, data, now)
   else
      self:set_failure(item, err or "read failed", now)
   end
end

function M:read_bus(name, roms, now)
   local bus, open_err = self:open_bus(name)
   if not bus then
      for _, rom in ipairs(roms) do
         self:record(name, rom, nil, open_err, now)
      end
      return open_err
   end
   local ok, convert_err = ds.start_convert(bus, nil)
   if not ok then
      for _, rom in ipairs(roms) do
         self:record(name, rom, nil, convert_err or "convert_failed", now)
      end
   else
      sleep(800)
      for _, rom in ipairs(roms) do
         local data, read_err = self:read_one(bus, rom)
         self:record(name, rom, data, read_err, now)
      end
   end
   bus:close()
   return nil
end

function M:read_cycle()
   local cfg = self.cfg
   local now = os.time()
   local errors = {}
   local map = group_by_bus(cfg)

   for _, name in ipairs(BUS_NAMES) do
      local list = map[name]
      if list and #list > 0 then
         local roms = {}
         for _, item in ipairs(list) do
            roms[#roms + 1] = item.sensor.rom
         end
         local err = self:read_bus(name, roms, now)
         if err then
            errors[name] = err
         end
      end
   end

   self.last_cycle = now
   return errors
end

function M:read_service()
   local now = os.time()
   for _, name in ipairs(BUS_NAMES) do
      local roms = self.discovered[name]
      if roms and #roms > 0 then
         self:read_bus(name, roms, now)
      end
   end
   self.last_cycle = now
end

function M:has_discovered()
   for _, name in ipairs(BUS_NAMES) do
      if self.discovered[name] and #self.discovered[name] > 0 then
         return true
      end
   end
   return false
end

function M:scan_all()
   local result = { buses = {}, errors = {} }
   local now = os.time()
   for _, name in ipairs(BUS_NAMES) do
      local bus, open_err = self:open_bus(name)
      if not bus then
         result.errors[#result.errors + 1] = name .. ": " .. tostring(open_err)
      else
         local entry = { name = name, roms = {} }
         local roms = ds.search(bus)
         self.discovered[name] = roms
         local converted, convert_err = true, nil
         if #roms > 0 then
            converted, convert_err = ds.start_convert(bus, nil)
            if converted then
               sleep(800)
            end
         end
         for _, rom in ipairs(roms) do
            local data, err
            if converted then
               data, err = self:read_one(bus, rom)
            else
               err = convert_err or "convert_failed"
            end
            self:record(name, rom, data, err, now)
            entry.roms[#entry.roms + 1] = {
               rom = rom,
               temp = data and data.temp or nil,
               err = err,
            }
         end
         result.buses[#result.buses + 1] = entry
         bus:close()
      end
   end
   self.scan_result = result
   return result
end

local function add_unique(t, value)
   for _, x in ipairs(t) do
      if x == value then
         return
      end
   end
   t[#t + 1] = value
end

local function avg_value(t)
   if #t == 0 then
      return nil
   end
   local sum = 0
   for _, value in ipairs(t) do
      sum = sum + value
   end
   return sum / #t
end

local function max_value(t)
   if #t == 0 then
      return nil
   end
   local value = t[1]
   for i = 2, #t do
      if t[i] > value then
         value = t[i]
      end
   end
   return value
end

function M:snapshot(now)
   now = now or os.time()
   local cfg = self.cfg
   local c = cfg.control
   local out = {
      rooms = {},
      floors = {},
      water = {},
      diagnostics = {},
      faults = {},
      warnings = {},
      raw = {},
   }

   for key, sensor in pairs(cfg.sensors or {}) do
      local last = self.last[key]
      local item = {
         key = key,
         bus = sensor.bus,
         rom = sensor.rom,
         role = sensor.role,
         label = sensor.label,
         temp = last and last.temp or nil,
         ts = last and last.ts or nil,
         ok = false,
         stale = true,
         err = last and last.err or "not_read",
      }
      if last and last.ok and last.ts and (now - last.ts) <= c.stale_after_sec then
         item.ok = true
         item.stale = false
         item.err = nil
         if "room" == sensor.role then
            out.rooms[#out.rooms + 1] = item.temp
         elseif "floor" == sensor.role then
            out.floors[#out.floors + 1] = item.temp
         elseif "supply" == sensor.role or "return" == sensor.role or "pump" == sensor.role then
            out.water[#out.water + 1] = item.temp
         end
      else
         add_unique(out.warnings, "sensor_failed:" .. (sensor.label or key))
      end
      out.diagnostics[#out.diagnostics + 1] = item
      out.raw[key] = item
   end

   local function role_values(role)
      local values = {}
      for _, item in ipairs(out.diagnostics) do
         if item.ok and item.role == role then
            values[#values + 1] = item.temp
         end
      end
      return values
   end

   out.actual = {
      room = avg_value(out.rooms),
      floor = max_value(out.floors),
      supply = avg_value(role_values("supply")),
      return_temp = avg_value(role_values("return")),
      pump = avg_value(role_values("pump")),
   }

   if #out.rooms > 0 and #out.floors > 0 then
      local rmin, rmax = out.rooms[1], out.rooms[1]
      for _, v in ipairs(out.rooms) do
         rmin = math.min(rmin, v)
         rmax = math.max(rmax, v)
      end
      local fmin, fmax = out.floors[1], out.floors[1]
      for _, v in ipairs(out.floors) do
         fmin = math.min(fmin, v)
         fmax = math.max(fmax, v)
      end
      if rmax - rmin > c.mismatch_warn then
         add_unique(out.warnings, "room_sensor_mismatch")
      end
      if fmax - fmin > c.mismatch_warn then
         add_unique(out.warnings, "floor_sensor_mismatch")
      end
   end

   return out
end

return M
