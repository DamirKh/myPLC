local pin = require("modules.pin")

return function(t)
   t.test("PIN must be exactly four digits", function()
      t.assert_true(pin.validate("1234"))
      t.assert_true(pin.validate("0000"))
      t.assert_false(pin.validate("123"))
      t.assert_false(pin.validate("12345"))
      t.assert_false(pin.validate("12a4"))
      t.assert_false(pin.validate(""))
   end)

   t.test("hex encoder", function()
      t.assert_eq(pin.hex("AB"), "4142")
   end)

   t.test("constant comparison", function()
      t.assert_true(pin.equal("abc", "abc"))
      t.assert_false(pin.equal("abc", "abd"))
      t.assert_false(pin.equal("abc", "ab"))
   end)

   t.test("trusted LAN accepts same /24", function()
      t.assert_true(pin.is_trusted("192.168.43.10", "192.168.43.44"))
   end)

   t.test("trusted LAN rejects other subnet", function()
      t.assert_false(pin.is_trusted("192.168.44.10", "192.168.43.44"))
   end)

   t.test("trusted LAN accepts loopback", function()
      t.assert_true(pin.is_trusted("127.0.0.1", "192.168.43.44"))
      t.assert_true(pin.is_trusted("::1", "192.168.43.44"))
   end)

   t.test("trusted LAN accepts same IPv6 /64", function()
      t.assert_true(pin.is_trusted("fd00:1234:5678:9abc::10", "fd00:1234:5678:9abc::1"))
      t.assert_false(pin.is_trusted("fd00:1234:5678:9abd::10", "fd00:1234:5678:9abc::1"))
   end)

   t.test("PIN setup allows AP regardless of subnet", function()
      t.assert_true(pin.setup_allowed("192.0.0.1", "192.168.190.0", "ap"))
      t.assert_true(pin.setup_allowed("10.0.0.2", "192.168.43.44", "AP"))
   end)

   t.test("PIN setup keeps LAN check outside AP", function()
      t.assert_true(pin.setup_allowed("192.168.43.10", "192.168.43.44", "sta"))
      t.assert_false(pin.setup_allowed("192.0.0.1", "192.168.190.0", "sta"))
      t.assert_false(pin.setup_allowed("192.0.0.1", "192.168.190.0", nil))
      t.assert_true(pin.setup_allowed("127.0.0.1", "192.168.43.44", nil))
   end)
end
