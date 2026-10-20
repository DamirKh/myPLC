local config = require("modules.config")

return function(t)
   t.test("defaults validate", function()
      local ok, errors = config.validate(config.defaults())
      t.assert_true(ok, table.concat(errors or {}, ", "))
   end)

   t.test("pin conflict rejected", function()
      local cfg = config.defaults()
      cfg.pins.control_a = cfg.pins.diag
      local ok = config.validate(cfg)
      t.assert_false(ok)
   end)

   t.test("control ready after assigning roles", function()
      local cfg = config.defaults()
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF00", "room", "A room", 0)
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF01", "floor", "A floor", 0)
      config.set_sensor(cfg, "control_b", "28AABBCCDDEEFF02", "room", "B room", 0)
      config.set_sensor(cfg, "control_b", "28AABBCCDDEEFF03", "floor", "B floor", 0)
      local ready = config.control_ready(cfg)
      t.assert_true(ready)
   end)

   t.test("duplicate room role rejected", function()
      local cfg = config.defaults()
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF00", "room", "", 0)
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF01", "room", "", 0)
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF02", "floor", "", 0)
      local ok = config.validate(cfg)
      t.assert_false(ok)
   end)

   t.test("missing roles are warnings not errors", function()
      local cfg = config.defaults()
      local ok, errors, warnings = config.validate(cfg)
      t.assert_true(ok, table.concat(errors or {}, ", "))
      t.assert_true(#warnings >= 2)
   end)

   t.test("merge keeps defaults for missing fields", function()
      local merged = config.merge(config.defaults(), { control = { floor_limit = 30 } })
      t.assert_eq(merged.control.floor_limit, 30)
      t.assert_eq(merged.control.target_room, 22.0)
   end)

   t.test("MQTT host validation accepts addresses and names", function()
      t.assert_true(config.valid_mqtt_host("192.168.43.202"))
      t.assert_true(config.valid_mqtt_host("localhost"))
      t.assert_true(config.valid_mqtt_host("broker.local"))
      t.assert_true(config.valid_mqtt_host("my-broker.lan"))
      t.assert_true(config.valid_mqtt_host("2001:db8::1"))
      t.assert_false(config.valid_mqtt_host("192.168..43.202"))
      t.assert_false(config.valid_mqtt_host("192.168.43.202:1883"))
      t.assert_false(config.valid_mqtt_host("999.168.43.202"))
      t.assert_false(config.valid_mqtt_host(""))
   end)

   t.test("enabled MQTT rejects malformed host and port", function()
      local cfg = config.defaults()
      cfg.mqtt.enabled = true
      cfg.mqtt.host = "192.168..43.202"
      local ok = config.validate(cfg)
      t.assert_false(ok)

      cfg.mqtt.host = "192.168.43.202"
      cfg.mqtt.port = 0
      ok = config.validate(cfg)
      t.assert_false(ok)

      cfg.mqtt.port = 1883
      local valid, errors = config.validate(cfg)
      t.assert_true(valid, table.concat(errors or {}, ", "))
   end)

   t.test("setpoint bounds must be ordered and contain base target", function()
      local cfg = config.defaults()
      cfg.ui.public_setpoint_min = 18
      cfg.ui.public_setpoint_max = 26
      local ok, errors = config.validate(cfg)
      t.assert_true(ok, table.concat(errors or {}, ", "))

      cfg.ui.public_setpoint_min = 26
      cfg.ui.public_setpoint_max = 18
      ok = config.validate(cfg)
      t.assert_false(ok)

      cfg.ui.public_setpoint_min = 24
      cfg.ui.public_setpoint_max = 28
      ok = config.validate(cfg)
      t.assert_false(ok)
   end)
end
