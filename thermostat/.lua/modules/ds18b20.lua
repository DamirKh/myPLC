local M = {}

M.SEARCH_ROM = 0xF0
M.READ_ROM = 0x33
M.MATCH_ROM = 0x55
M.SKIP_ROM = 0xCC
M.CONVERT_T = 0x44
M.READ_SCRATCHPAD = 0xBE
M.FAMILY = 0x28

local function byte_at(data, i)
   if "string" == type(data) then
      return data:byte(i)
   end
   return data[i]
end

local function length_of(data)
   if "string" == type(data) then
      return #data
   end
   return #data
end

function M.crc8(data, crc)
   crc = crc or 0
   for i = 1, length_of(data) do
      local b = byte_at(data, i)
      for _ = 1, 8 do
         local mix = (crc ~ b) & 1
         crc = crc >> 1
         if mix ~= 0 then
            crc = crc ~ 0x8C
         end
         b = b >> 1
      end
   end
   return crc & 0xFF
end

function M.rom_from_string(text)
   local hex = tostring(text):gsub("[^%x]", "")
   if 16 ~= #hex then
      return nil, "ROM must contain 16 hex digits"
   end
   local rom = {}
   for i = 1, 8 do
      rom[i] = tonumber(hex:sub((i - 1) * 2 + 1, i * 2), 16)
   end
   return rom
end

function M.rom_to_string(rom)
   local out = {}
   for i = 1, 8 do
      out[i] = string.format("%02X", byte_at(rom, i))
   end
   return table.concat(out)
end

function M.rom_crc_ok(rom)
   local first = {}
   for i = 1, 7 do
      first[i] = byte_at(rom, i)
   end
   return M.crc8(first) == byte_at(rom, 8)
end

function M.decode_temperature(lsb, msb)
   local raw = lsb | (msb << 8)
   if raw >= 0x8000 then
      raw = raw - 0x10000
   end
   return raw / 16, raw
end

function M.parse_scratchpad(data)
   if length_of(data) ~= 9 then
      return nil, "scratchpad must be 9 bytes"
   end
   local bytes = {}
   for i = 1, 9 do
      bytes[i] = byte_at(data, i)
   end
   if M.crc8({ table.unpack(bytes, 1, 8) }) ~= bytes[9] then
      return nil, "CRC error"
   end
   local config = bytes[5]
   local resolution = (config >> 5) & 3
   if resolution > 3 then
      return nil, "invalid resolution"
   end
   local temp, raw = M.decode_temperature(bytes[1], bytes[2])
   if temp < -55 or temp > 125 then
      return nil, "temperature out of range"
   end
   return {
      temp = temp,
      raw = raw,
      config = config,
      resolution = resolution,
      power_on_reset = temp == 85.0,
      bytes = bytes,
   }
end

local function read_bit(bus)
   return bus:read_bit()
end

local function write_bit(bus, bit)
   return bus:write_bit(bit and true or false)
end

function M.search(bus)
   local devices = {}
   local last_discrepancy = 0
   local rom_bits = {}

   for _ = 1, 256 do
      if not bus:reset() then
         break
      end
      bus:write_byte(M.SEARCH_ROM)

      local last_zero = 0
      local aborted = false
      for bit = 1, 64 do
         local id_bit = read_bit(bus)
         local cmp_bit = read_bit(bus)
         if nil == id_bit or nil == cmp_bit then
            aborted = true
            break
         end
         if id_bit and cmp_bit then
            aborted = true
            break
         end

         local direction
         if not id_bit and not cmp_bit then
            if bit < last_discrepancy then
               direction = rom_bits[bit] or 0
            elseif bit == last_discrepancy then
               direction = 1
            else
               direction = 0
            end
            if 0 == direction then
               last_zero = bit
            end
         else
            direction = id_bit and 1 or 0
         end

         rom_bits[bit] = direction
         write_bit(bus, 1 == direction)
      end

      if aborted then
         break
      end

      local rom = {}
      for i = 1, 8 do
         local b = 0
         for bit = 0, 7 do
            if 1 == rom_bits[i * 8 - 7 + bit] then
               b = b | (1 << bit)
            end
         end
         rom[i] = b
      end

      if M.rom_crc_ok(rom) then
         devices[#devices + 1] = M.rom_to_string(rom)
      end

      last_discrepancy = last_zero
      if 0 == last_zero then
         break
      end
   end

   return devices
end

function M.read_rom(bus)
   if not bus:reset() then
      return nil, "no presence"
   end
   bus:write_byte(M.READ_ROM)
   local rom = {}
   for i = 1, 8 do
      rom[i] = bus:read_byte()
   end
   return rom
end

function M.start_convert(bus, rom)
   if not bus:reset() then
      return nil, "no presence"
   end
   if rom then
      bus:write_byte(M.MATCH_ROM)
      for i = 1, 8 do
         bus:write_byte(byte_at(rom, i))
      end
   else
      bus:write_byte(M.SKIP_ROM)
   end
   bus:write_byte(M.CONVERT_T)
   return true
end

function M.read_scratchpad(bus, rom)
   if not bus:reset() then
      return nil, "no presence"
   end
   bus:write_byte(M.MATCH_ROM)
   for i = 1, 8 do
      bus:write_byte(byte_at(rom, i))
   end
   bus:write_byte(M.READ_SCRATCHPAD)
   local data = {}
   for i = 1, 9 do
      data[i] = bus:read_byte()
   end
   return M.parse_scratchpad(data)
end

function M.describe(rom)
   return M.rom_to_string(rom)
end

return M
