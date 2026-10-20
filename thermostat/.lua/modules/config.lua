local M = {}

M.ROLES = {
   room = "room",
   floor = "floor",
   supply = "supply",
   ["return"] = "return",
   pump = "pump",
   extra = "extra",
}

local CONTROL_BUSES = { "control_a", "control_b" }

local DEFAULTS = {
   version = 1,
   pins = {
      diag = 4,
      control_a = 5,
      control_b = 6,
      ssr = 7,
      ssr_active_high = true,
      rgb = 48,
      rgb_enabled = true,
      rgb_brightness = 0.25,
   },
   control = {
      target_room = 22.0,
      floor_limit = 28.0,
      room_hysteresis = 0.3,
      floor_hysteresis = 0.5,
      min_on_sec = 180,
      min_off_sec = 180,
      pump_exercise_hours = 24,
      pump_exercise_sec = 300,
      frost_enabled = false,
      frost_threshold = 5.0,
      stale_after_sec = 20,
      recovery_reads = 3,
      mismatch_warn = 2.0,
      fault_policy = "off",
   },
   schedule = {
      enabled = false,
      utc_offset_minutes = 180,
      blocks = {},
   },
   mqtt = {
      enabled = false,
      host = "",
      port = 1883,
      tls = false,
      username = "",
      password = "",
      base_topic = "home/floor/thermostat",
      ha_discovery = false,
   },
   history = {
      sample_sec = 60,
      ram_hours = 48,
      flash_sample_sec = 300,
      max_bytes = 1048576,
   },
   ui = {
      public_setpoint = true,
      public_setpoint_min = 16.0,
      public_setpoint_max = 28.0,
   },
   security = {
      pin_salt = "",
      pin_hash = "",
      pin_iterations = 20000,
      session_minutes = 30,
   },
   sensors = {},
}

local function is_number(v)
   return "number" == type(v)
end

local function copy(v)
   if "table" ~= type(v) then
      return v
   end
   local t = {}
   for k, x in pairs(v) do
      t[k] = copy(x)
   end
   return t
end

local function merge(base, override)
   local out = copy(base)
   if "table" ~= type(override) then
      return out
   end
   for k, v in pairs(override) do
      if "table" == type(v) and "table" == type(out[k]) then
         out[k] = merge(out[k], v)
      else
         out[k] = copy(v)
      end
   end
   return out
end

function M.defaults()
   return copy(DEFAULTS)
end

function M.merge(base, override)
   return merge(base, override)
end

function M.sensor_key(bus, rom)
   return tostring(bus) .. ":" .. tostring(rom):upper()
end

function M.valid_role(role)
   return "string" == type(role) and nil ~= M.ROLES[role]
end

function M.control_buses()
   return { CONTROL_BUSES[1], CONTROL_BUSES[2] }
end

function M.roles_by_bus(cfg, bus)
   local out = {}
   for _, sensor in pairs(cfg.sensors or {}) do
      if sensor.bus == bus then
         out[#out + 1] = sensor
      end
   end
   table.sort(out, function(a, b)
      return (a.rom or "") < (b.rom or "")
   end)
   return out
end

function M.count_role(cfg, bus, role)
   local n = 0
   for _, sensor in pairs(cfg.sensors or {}) do
      if sensor.bus == bus and sensor.role == role then
         n = n + 1
      end
   end
   return n
end

function M.control_ready(cfg)
   for _, bus in ipairs(CONTROL_BUSES) do
      if 1 ~= M.count_role(cfg, bus, "room") or 1 ~= M.count_role(cfg, bus, "floor") then
         return false, bus
      end
   end
   return true
end

function M.set_sensor(cfg, bus, rom, role, label, offset)
   cfg.sensors = cfg.sensors or {}
   local key = M.sensor_key(bus, rom)
   cfg.sensors[key] = {
      bus = bus,
      rom = tostring(rom):upper(),
      role = role,
      label = label or "",
      offset = tonumber(offset) or 0,
   }
   return cfg.sensors[key]
end

function M.remove_sensor(cfg, bus, rom)
   cfg.sensors = cfg.sensors or {}
   cfg.sensors[M.sensor_key(bus, rom)] = nil
end

function M.validate(cfg)
   local errors = {}
   local warnings = {}

   if "table" ~= type(cfg) then
      return false, { "config is not a table" }, warnings
   end
   if cfg.version ~= 1 then
      errors[#errors + 1] = "unsupported config version"
   end

   local pins = cfg.pins or {}
   local used = {}
   local pin_names = { "diag", "control_a", "control_b", "ssr" }
   if pins.rgb_enabled ~= false then
      pin_names[#pin_names + 1] = "rgb"
   end
   for _, name in ipairs(pin_names) do
      local pin = pins[name]
      if not is_number(pin) or pin < 0 or pin > 48 then
         errors[#errors + 1] = "invalid pin " .. name
      elseif used[pin] then
         errors[#errors + 1] = "pin conflict on " .. tostring(pin)
      else
         used[pin] = name
      end
   end
   if pins.rgb_brightness ~= nil and (not is_number(pins.rgb_brightness) or pins.rgb_brightness < 0 or pins.rgb_brightness > 1) then
      errors[#errors + 1] = "rgb_brightness out of range"
   end

   local c = cfg.control or {}
   local numeric = {
      "target_room", "floor_limit", "room_hysteresis", "floor_hysteresis",
      "min_on_sec", "min_off_sec", "pump_exercise_hours", "pump_exercise_sec",
      "frost_threshold", "stale_after_sec", "recovery_reads", "mismatch_warn",
   }
   for _, name in ipairs(numeric) do
      if not is_number(c[name]) then
         errors[#errors + 1] = "control." .. name .. " must be a number"
      end
   end
   if is_number(c.target_room) and (c.target_room < 5 or c.target_room > 35) then
      errors[#errors + 1] = "target_room out of range"
   end
   if is_number(c.floor_limit) and (c.floor_limit < 10 or c.floor_limit > 45) then
      errors[#errors + 1] = "floor_limit out of range"
   end
   if is_number(c.room_hysteresis) and (c.room_hysteresis < 0 or c.room_hysteresis > 5) then
      errors[#errors + 1] = "room_hysteresis out of range"
   end
   if is_number(c.floor_hysteresis) and (c.floor_hysteresis < 0 or c.floor_hysteresis > 5) then
      errors[#errors + 1] = "floor_hysteresis out of range"
   end
   if c.fault_policy ~= "off" then
      errors[#errors + 1] = "only fault_policy=off is supported"
   end

   local ui = cfg.ui or {}
   local min_setpoint = ui.public_setpoint_min
   local max_setpoint = ui.public_setpoint_max
   if not is_number(min_setpoint) or min_setpoint < 5 or min_setpoint > 35 then
      errors[#errors + 1] = "public_setpoint_min out of range"
   end
   if not is_number(max_setpoint) or max_setpoint < 5 or max_setpoint > 35 then
      errors[#errors + 1] = "public_setpoint_max out of range"
   end
   if is_number(min_setpoint) and is_number(max_setpoint) and min_setpoint >= max_setpoint then
      errors[#errors + 1] = "public_setpoint_min must be less than public_setpoint_max"
   elseif is_number(c.target_room) and is_number(min_setpoint) and is_number(max_setpoint)
      and (c.target_room < min_setpoint or c.target_room > max_setpoint) then
      errors[#errors + 1] = "target_room must be inside public setpoint range"
   end

   local sec = cfg.security or {}
   if "string" ~= type(sec.pin_salt) or "string" ~= type(sec.pin_hash) then
      errors[#errors + 1] = "security PIN fields must be strings"
   elseif "" ~= sec.pin_hash and "" == sec.pin_salt then
      errors[#errors + 1] = "pin_hash requires pin_salt"
   end
   if not is_number(sec.pin_iterations) or sec.pin_iterations < 1 or sec.pin_iterations > 1000000 then
      errors[#errors + 1] = "pin_iterations out of range"
   end
   if not is_number(sec.session_minutes) or sec.session_minutes < 1 or sec.session_minutes > 1440 then
      errors[#errors + 1] = "session_minutes out of range"
   end

   local seen = {}
   for key, sensor in pairs(cfg.sensors or {}) do
      if "table" ~= type(sensor) then
         errors[#errors + 1] = "sensor " .. key .. " is not a table"
      else
         if not sensor.bus or not sensor.rom then
            errors[#errors + 1] = "sensor " .. key .. " missing bus/rom"
         elseif "diag" ~= sensor.bus and "control_a" ~= sensor.bus and "control_b" ~= sensor.bus then
            errors[#errors + 1] = "sensor " .. key .. " has invalid bus"
         elseif 16 ~= #tostring(sensor.rom):gsub("[^%x]", "") then
            errors[#errors + 1] = "sensor " .. key .. " has invalid ROM"
         end
         if not M.valid_role(sensor.role) then
            errors[#errors + 1] = "sensor " .. key .. " has invalid role"
         end
         if seen[key] then
            errors[#errors + 1] = "duplicate sensor key " .. key
         end
         seen[key] = true
      end
   end

   for _, bus in ipairs(CONTROL_BUSES) do
      local rooms = M.count_role(cfg, bus, "room")
      local floors = M.count_role(cfg, bus, "floor")
      if rooms > 1 then
         errors[#errors + 1] = bus .. " has more than one room sensor"
      end
      if floors > 1 then
         errors[#errors + 1] = bus .. " has more than one floor sensor"
      end
      if rooms == 0 or floors == 0 then
         warnings[#warnings + 1] = bus .. " is not fully configured"
      end
   end

   return #errors == 0, errors, warnings
end

function M.load(io, filename)
   local name = filename or "config.json"
   local cfg = M.defaults()
   if not io then
      return cfg, false, "no io"
   end
   local ok, rwfile = pcall(require, "rwfile")
   if not ok then
      return cfg, false, tostring(rwfile)
   end
   local stored, err = rwfile.json(io, name)
   if not stored then
      return cfg, false, err or "config not found"
   end
   local merged = merge(cfg, stored)
   local valid, errors = M.validate(merged)
   if not valid then
      return cfg, false, errors
   end
   return merged, true
end

function M.save(io, cfg, filename)
   local name = filename or "config.json"
   local valid, errors = M.validate(cfg)
   if not valid then
      return false, errors
   end
   local ok, rwfile = pcall(require, "rwfile")
   if not ok then
      return false, tostring(rwfile)
   end
   local saved, err = rwfile.json(io, name, cfg)
   if not saved then
      return false, err
   end
   return true
end

return M
