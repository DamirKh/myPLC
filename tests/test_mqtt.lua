local bridge = require("modules.mqtt_bridge")

return function(t)
   t.test("invalid MQTT host is rejected before connect", function()
      local instance, err = bridge.new({
         mqtt = { enabled = true, host = "192.168..43.202" },
      }, {})
      t.assert_eq(instance, nil)
      t.assert_eq(err, "invalid host")
   end)

   t.test("disabled MQTT bridge does not connect", function()
      local instance, err = bridge.new({ mqtt = { enabled = false } }, {})
      t.assert_eq(instance, nil)
      t.assert_eq(err, "disabled")
   end)
end
