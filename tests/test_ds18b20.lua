local ds = require("modules.ds18b20")

local function make_rom(serial)
   local rom = { 0x28 }
   for i = 1, 6 do
      rom[#rom + 1] = serial[i] or 0
   end
   rom[8] = ds.crc8(rom)
   return rom
end

local FakeBus = {}
FakeBus.__index = FakeBus

function FakeBus.new(roms, present)
   local devices = {}
   for _, rom in ipairs(roms) do
      devices[#devices + 1] = rom
   end
   return setmetatable({
      devices = devices,
      present = present ~= false,
      searching = false,
      candidates = nil,
      bit_index = 0,
      phase = 0,
   }, FakeBus)
end

function FakeBus:reset()
   return self.present
end

function FakeBus:write_byte(cmd)
   if cmd == ds.SEARCH_ROM then
      self.searching = true
      self.candidates = {}
      for _, rom in ipairs(self.devices) do
         self.candidates[#self.candidates + 1] = rom
      end
      self.bit_index = 0
      self.phase = 0
   else
      self.searching = false
   end
end

local function bit_of(rom, index)
   local byte = rom[math.floor(index / 8) + 1]
   return (byte >> (index % 8)) & 1
end

function FakeBus:read_bit()
   if not self.searching then
      return true
   end
   local index = self.bit_index
   local id_bit, cmp_bit = 1, 1
   for _, rom in ipairs(self.candidates) do
      if 0 == bit_of(rom, index) then
         id_bit = 0
      else
         cmp_bit = 0
      end
   end
   local value = (0 == self.phase) and id_bit or cmp_bit
   self.phase = (self.phase + 1) % 2
   return 1 == value
end

function FakeBus:write_bit(dir)
   if not self.searching then
      return
   end
   local value = dir and 1 or 0
   local filtered = {}
   for _, rom in ipairs(self.candidates) do
      if bit_of(rom, self.bit_index) == value then
         filtered[#filtered + 1] = rom
      end
   end
   self.candidates = filtered
   self.bit_index = self.bit_index + 1
   self.phase = 0
end

function FakeBus:read_byte()
   return 0
end

return function(t)
   t.test("dallas crc8 check value", function()
      t.assert_eq(ds.crc8("123456789"), 0xA1)
   end)

   t.test("decode positive temperature", function()
      local temp, raw = ds.decode_temperature(0x91, 0x01)
      t.assert_near(temp, 25.0625, 0.0001)
      t.assert_eq(raw, 401)
   end)

   t.test("decode negative temperature", function()
      t.assert_near(ds.decode_temperature(0x5E, 0xFF), -10.125, 0.0001)
   end)

   t.test("parse valid scratchpad", function()
      local bytes = { 0x91, 0x01, 0x4B, 0x46, 0x7F, 0xFF, 0x0C, 0x10 }
      bytes[9] = ds.crc8(bytes)
      local data, err = ds.parse_scratchpad(bytes)
      t.assert_true(data, err)
      t.assert_near(data.temp, 25.0625, 0.0001)
      t.assert_false(data.power_on_reset)
   end)

   t.test("parse scratchpad rejects bad crc", function()
      local bytes = { 0x91, 0x01, 0x4B, 0x46, 0x7F, 0xFF, 0x0C, 0x10, 0x00 }
      local data, err = ds.parse_scratchpad(bytes)
      t.assert_eq(data, nil)
      t.assert_eq(err, "CRC error")
   end)

   t.test("parse scratchpad flags 85C power-on value", function()
      local bytes = { 0x50, 0x05, 0x4B, 0x46, 0x7F, 0xFF, 0x0C, 0x10 }
      bytes[9] = ds.crc8(bytes)
      local data = ds.parse_scratchpad(bytes)
      t.assert_true(data)
      t.assert_near(data.temp, 85.0, 0.0001)
      t.assert_true(data.power_on_reset)
   end)

   t.test("rom round trip", function()
      local rom = make_rom({ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 })
      local text = ds.rom_to_string(rom)
      local again = ds.rom_from_string(text)
      t.assert_eq(ds.rom_to_string(again), text)
      t.assert_true(ds.rom_crc_ok(again))
   end)

   t.test("search finds two sensors", function()
      local a = make_rom({ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66 })
      local b = make_rom({ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF })
      local bus = FakeBus.new({ a, b })
      local found = ds.search(bus)
      table.sort(found)
      local expected = { ds.rom_to_string(a), ds.rom_to_string(b) }
      table.sort(expected)
      t.assert_eq(#found, 2)
      t.assert_eq(found[1], expected[1])
      t.assert_eq(found[2], expected[2])
   end)

   t.test("search returns nothing without presence", function()
      local bus = FakeBus.new({}, false)
      t.assert_eq(#ds.search(bus), 0)
   end)
end
