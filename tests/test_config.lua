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

   t.test("AP jumper pins must be valid and unique", function()
      local cfg = config.defaults()
      cfg.pins.ap_jumper_in = cfg.pins.ap_jumper_out
      t.assert_false(config.validate(cfg))

      cfg = config.defaults()
      cfg.pins.ap_jumper_in = cfg.pins.ssr
      t.assert_false(config.validate(cfg))
   end)

   t.test("STA confirmation must be a boolean", function()
      local cfg = config.defaults()
      cfg.wifi.sta_confirmed = "yes"
      t.assert_false(config.validate(cfg))
   end)

   t.test("control ready with both pairs", function()
      local cfg = config.defaults()
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF00", "room", "A room", 0)
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF01", "floor", "A floor", 0)
      config.set_sensor(cfg, "control_b", "28AABBCCDDEEFF02", "room", "B room", 0)
      config.set_sensor(cfg, "control_b", "28AABBCCDDEEFF03", "floor", "B floor", 0)
      local ready = config.control_ready(cfg)
      t.assert_true(ready)
   end)

   t.test("control ready with a single pair", function()
      local cfg = config.defaults()
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF00", "room", "A room", 0)
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF01", "floor", "A floor", 0)
      local ready = config.control_ready(cfg)
      t.assert_true(ready)
   end)

   t.test("multiple room and floor sensors are allowed", function()
      local cfg = config.defaults()
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF00", "room", "", 0)
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF01", "room", "", 0)
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF02", "floor", "", 0)
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF03", "floor", "", 0)
      local ok, errors = config.validate(cfg)
      t.assert_true(ok, table.concat(errors or {}, ", "))
      t.assert_true(config.control_ready(cfg))
   end)

   t.test("multiple diag supply and return sensors are allowed", function()
      local cfg = config.defaults()
      config.set_sensor(cfg, "diag", "28AABBCCDDEEFF10", "supply", "", 0)
      config.set_sensor(cfg, "diag", "28AABBCCDDEEFF11", "supply", "", 0)
      config.set_sensor(cfg, "diag", "28AABBCCDDEEFF12", "return", "", 0)
      config.set_sensor(cfg, "diag", "28AABBCCDDEEFF13", "return", "", 0)
      local ok, errors = config.validate(cfg)
      t.assert_true(ok, table.concat(errors or {}, ", "))
   end)

   t.test("history stream settings are validated", function()
      local cfg = config.defaults()
      local ok = config.validate(cfg)
      t.assert_true(ok)
      cfg.history.room.sample_sec = 1
      ok = config.validate(cfg)
      t.assert_false(ok)
      cfg = config.defaults()
      cfg.history.pump.max_bytes = 100
      ok = config.validate(cfg)
      t.assert_false(ok)
   end)

   t.test("missing roles are warnings not errors", function()
      local cfg = config.defaults()
      local ok, errors, warnings = config.validate(cfg)
      t.assert_true(ok, table.concat(errors or {}, ", "))
      t.assert_true(#warnings >= 1)
   end)

   t.test("merge keeps defaults for missing fields", function()
      local merged = config.merge(config.defaults(), { control = { floor_limit = 30 } })
      t.assert_eq(merged.control.floor_limit, 30)
      t.assert_eq(merged.control.target_room, 22.0)
   end)

   t.test("WiFi mode and credentials are validated", function()
      local cfg = config.defaults()
      local ok = config.validate(cfg)
      t.assert_true(ok)

      cfg.wifi.mode = "sta"
      ok = config.validate(cfg)
      t.assert_false(ok)

      cfg.wifi.sta_ssid = "gft"
      cfg.wifi.sta_password_enc = "encrypted"
      ok = config.validate(cfg)
      t.assert_true(ok)

      cfg.wifi.mode = "bogus"
      ok = config.validate(cfg)
      t.assert_false(ok)
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

   t.test("max override hours default and range", function()
      local cfg = config.defaults()
      t.assert_eq(cfg.ui.max_override_hours, 6.0)

      cfg.ui.max_override_hours = 0.25
      t.assert_false(config.validate(cfg))

      cfg.ui.max_override_hours = 100
      t.assert_false(config.validate(cfg))
   end)

   t.test("ESP-NOW nodes are validated", function()
      local cfg = config.defaults()
      cfg.espnow.nodes["3c8427ca2754"] = { mac = "3c8427ca2754", label = "sensor" }
      local ok, errors = config.validate(cfg)
      t.assert_true(ok, table.concat(errors or {}, ", "))

      cfg.espnow.nodes["3c8427ca275"] = { mac = "3c8427ca275", label = "" }
      t.assert_false(config.validate(cfg))

      cfg = config.defaults()
      cfg.espnow.nodes["3c8427ca2754"] = { mac = "aabbccddeeff", label = "" }
      t.assert_false(config.validate(cfg))

      cfg = config.defaults()
      cfg.espnow.nodes["3c8427ca2754"] = { mac = "3c8427ca2754", label = string.rep("x", 65) }
      t.assert_false(config.validate(cfg))
   end)

   t.test("ESP-NOW provisioning window is bounded", function()
      local cfg = config.defaults()
      t.assert_eq(cfg.espnow.provision_window_sec, 45)
      cfg.espnow.provision_window_sec = 5
      t.assert_false(config.validate(cfg))
      cfg.espnow.provision_window_sec = 121
      t.assert_false(config.validate(cfg))
   end)

   t.test("ESP-NOW sensor buses require an allowlisted node", function()
      local cfg = config.defaults()
      local bus = "espnow:3c8427ca2754"
      config.set_sensor(cfg, bus, "28AABBCCDDEEFF00", "room", "", 0)
      t.assert_false(config.validate(cfg))
      cfg.espnow.nodes["3c8427ca2754"] = { mac = "3c8427ca2754", label = "" }
      local ok, errors = config.validate(cfg)
      t.assert_true(ok, table.concat(errors or {}, ", "))
      t.assert_true(config.valid_sensor_bus(bus))
      t.assert_false(config.valid_sensor_bus("espnow:bad"))
   end)

   t.test("control ready allows mixed sensor sources", function()
      local cfg = config.defaults()
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF00", "room", "", 0)
      config.set_sensor(cfg, "espnow:3c8427ca2754", "28AABBCCDDEEFF01", "floor", "", 0)
      cfg.espnow.nodes["3c8427ca2754"] = { mac = "3c8427ca2754", label = "" }
      t.assert_true(config.control_ready(cfg))
      t.assert_true(config.validate(cfg))

      cfg = config.defaults()
      config.set_sensor(cfg, "control_a", "28AABBCCDDEEFF00", "room", "", 0)
      t.assert_false(config.control_ready(cfg))
   end)

   t.test("ESP-NOW stale timeout is bounded", function()
      local cfg = config.defaults()
      t.assert_eq(cfg.espnow.stale_after_sec, 360)
      cfg.espnow.stale_after_sec = 100
      t.assert_false(config.validate(cfg))
      cfg.espnow.stale_after_sec = 3601
      t.assert_false(config.validate(cfg))
   end)
end
