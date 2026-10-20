local M = {}
M.__index = M

local function encode(value)
   if ba and ba.json and ba.json.encode then
      return ba.json.encode(value)
   end
   return nil
end

local function decode(value)
   if ba and ba.json and ba.json.decode then
      return ba.json.decode(value)
   end
   return nil
end

function M.new(cfg, handlers)
   local mcfg = cfg.mqtt or {}
   if not mcfg.enabled then
      return nil, "disabled"
   end
   local ok, mqttc = pcall(require, "mqttc")
   if not ok then
      return nil, tostring(mqttc)
   end
   local self = setmetatable({
      cfg = cfg,
      mcfg = mcfg,
      handlers = handlers or {},
      connected = false,
      mqtt = nil,
      mqttc = mqttc,
   }, M)
   return self
end

function M:topic(suffix)
   return (self.mcfg.base_topic or "home/floor/thermostat") .. "/" .. suffix
end

function M:on_status(kind, code, status)
   if "mqtt" == kind and "connect" == code and status and 0 == status.reasoncode then
      self.connected = true
      self.mqtt:subscribe(self:topic("set/#"))
      self:publish(self:topic("availability"), "online", true)
      if self.handlers.on_connect then
         self.handlers.on_connect(self)
      end
      return true
   end
   self.connected = false
   self:publish(self:topic("availability"), "offline", true)
   return true
end

function M:on_publish(topic, payload)
   local data = decode(payload)
   if not data then
      return
   end
   if self.handlers.on_command then
      self.handlers.on_command(topic, data)
   end
end

function M:start()
   if self.mqtt then
      return true
   end
   local options = {
      port = self.mcfg.port or 1883,
      secure = self.mcfg.tls and true or false,
   }
   if self.mcfg.username and "" ~= self.mcfg.username then
      options.username = self.mcfg.username
      options.password = self.mcfg.password or ""
   end
   local mqtt, err = self.mqttc.create(
      self.mcfg.host,
      function(kind, code, status)
         return self:on_status(kind, code, status)
      end,
      function(topic, payload)
         return self:on_publish(topic, payload)
      end,
      options
   )
   if not mqtt then
      return nil, err
   end
   self.mqtt = mqtt
   return true
end

function M:publish(topic, value, retain)
   if not self.mqtt then
      return nil, "not started"
   end
   local payload = value
   if "table" == type(value) then
      payload = encode(value)
   end
   if not payload then
      return nil, "encode failed"
   end
   return self.mqtt:publish(topic, payload, { retain = retain and true or false })
end

function M:stop()
   if self.mqtt then
      self:publish(self:topic("availability"), "offline", true)
      self.mqtt:disconnect()
      self.mqtt = nil
   end
   self.connected = false
end

function M:publish_state(state)
   return self:publish(self:topic("state"), state, true)
end

function M:publish_discovery(state, node_id)
   if not self.mcfg.ha_discovery then
      return
   end
   local base = self:topic("")
   local device = {
      identifiers = { node_id },
      name = "Floor thermostat",
      manufacturer = "myPLC",
      model = "Xedge32 thermostat",
   }
   local prefix = "homeassistant/"
   local sensors = {
      { id = "room", name = "Room temperature", key = "room" },
      { id = "floor", name = "Floor temperature", key = "floor" },
      { id = "supply", name = "Supply temperature", key = "supply" },
      { id = "return", name = "Return temperature", key = "return_temp" },
   }
   for _, s in ipairs(sensors) do
      self:publish(prefix .. "sensor/" .. node_id .. "_" .. s.id .. "/config", {
         name = s.name,
         unique_id = node_id .. "_" .. s.id,
         state_topic = base .. "state",
         value_template = "{{ value_json." .. s.key .. " }}",
         unit_of_measurement = "°C",
         device_class = "temperature",
         state_class = "measurement",
         availability_topic = base .. "availability",
         device = device,
      }, true)
   end
   self:publish(prefix .. "climate/" .. node_id .. "/config", {
      name = "Floor thermostat",
      unique_id = node_id .. "_climate",
      modes = { "off", "heat" },
      mode_state_topic = base .. "state",
      mode_state_template = "{{ value_json.mode }}",
      mode_command_topic = base .. "set/mode",
      current_temperature_topic = base .. "state",
      current_temperature_template = "{{ value_json.room }}",
      temperature_state_topic = base .. "state",
      temperature_state_template = "{{ value_json.target }}",
      temperature_command_topic = base .. "set/target",
      action_topic = base .. "state",
      action_template = "{{ 'heating' if value_json.pump else 'idle' }}",
      min_temp = state.setpoint_min or 16,
      max_temp = state.setpoint_max or 28,
      temp_step = 0.5,
      availability_topic = base .. "availability",
      device = device,
   }, true)
end

return M
