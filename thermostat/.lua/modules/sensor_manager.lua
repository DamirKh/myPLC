local ds = require("modules.ds18b20")
local M = {}
M.__index = M

local function sleep(ms)
   if ba and ba.sleep then
      ba.sleep(ms)
   end
end

function M.new(cfg, buses)
   return setmetatable({
      cfg = cfg,
      buses = buses or {},
      last = {},
      last_cycle = nil,
      scan_result = nil,
   }, M)
end

function M:bus(name)
   return self.buses[name]
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

function M:read_cycle()
   local cfg = self.cfg
   local now = os.time()
   local converted = {}
   local errors = {}

   for name, bus in pairs(self.buses) do
      local ok, err = ds.start_convert(bus, nil)
      if ok then
         converted[#converted + 1] = name
      else
         errors[name] = err or "convert failed"
      end
   end

   if #converted > 0 then
      sleep(800)
   end

   for key, sensor in pairs(cfg.sensors or {}) do
      local bus = self.buses[sensor.bus]
      if not bus then
         self.last[key] = {
            ok = false,
            err = "bus_missing",
            ts = now,
            temp = self.last[key] and self.last[key].temp,
         }
      else
         local data, err = self:read_one(bus, sensor.rom)
         if data then
            local prev = self.last[key]
            self.last[key] = {
               ok = true,
               temp = data.temp + (sensor.offset or 0),
               raw = data.raw,
               ts = now,
               good_count = (prev and prev.good_count or 0) + 1,
               fail_count = 0,
            }
         else
            local prev = self.last[key] or {}
            self.last[key] = {
               ok = false,
               err = err,
               ts = now,
               temp = prev.temp,
               good_count = 0,
               fail_count = (prev.fail_count or 0) + 1,
            }
         end
      end
   end

   self.last_cycle = now
   return errors
end

function M:scan_all()
   local result = { buses = {}, errors = {} }
   for _, name in ipairs({ "diag", "control_a", "control_b" }) do
      local bus = self.buses[name]
      if not bus then
         result.errors[#result.errors + 1] = name .. ": bus_missing"
      else
         local roms = ds.search(bus)
         local entry = { name = name, roms = {} }
         for _, rom in ipairs(roms) do
            local data, err = self:read_one(bus, rom)
            entry.roms[#entry.roms + 1] = {
               rom = rom,
               temp = data and data.temp or nil,
               err = err,
            }
         end
         result.buses[#result.buses + 1] = entry
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
