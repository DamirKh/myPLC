local M = {}

local function hex_byte(c)
   return string.format("%02x", c:byte())
end

function M.hex(value)
   return (tostring(value or ""):gsub(".", hex_byte))
end

function M.normalize_mac(value)
   local text = tostring(value or ""):lower():gsub("[^%x]", "")
   if 12 == #text then
      return text
   end
   return nil
end

function M.valid_mac_hex(value)
   local text = tostring(value or "")
   return 12 == #text and text:match("^%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

function M.mac_text(value)
   local text = M.normalize_mac(value)
   if not text then
      return tostring(value or "")
   end
   return text:sub(1, 2) .. ":" .. text:sub(3, 4) .. ":" .. text:sub(5, 6)
      .. ":" .. text:sub(7, 8) .. ":" .. text:sub(9, 10) .. ":" .. text:sub(11, 12)
end

function M.equal(a, b)
   a, b = tostring(a or ""), tostring(b or "")
   if #a ~= #b then
      return false
   end
   local diff = 0
   for i = 1, #a do
      diff = diff | (a:byte(i) ~ b:byte(i))
   end
   return 0 == diff
end

function M.random_token(ba)
   if ba and ba.aeskey then
      local ok, key = pcall(ba.aeskey, 4)
      if ok and key and #key >= 4 then
         return key:sub(1, 4)
      end
   end
   if ba and ba.rnd then
      local out = {}
      for i = 1, 4 do
         out[i] = string.char(ba.rnd(0, 255))
      end
      return table.concat(out)
   end
   return nil, "RNG unavailable"
end

function M.build_prov(controller_mac, token, channel, version)
   if "string" ~= type(controller_mac) or 6 ~= #controller_mac then
      return nil, "controller MAC must be 6 bytes"
   end
   if "string" ~= type(token) or 4 ~= #token then
      return nil, "token must be 4 bytes"
   end
   channel = tonumber(channel)
   if not channel or channel < 1 or channel > 255 then
      return nil, "invalid channel"
   end
   version = tonumber(version) or 1
   return "PROV" .. string.char(version) .. controller_mac .. token .. string.char(channel)
end

function M.parse_pok(data, src, token)
   if "string" ~= type(data) or #data < 14 then
      return nil, "short packet"
   end
   if "POK" ~= data:sub(1, 3) then
      return nil, "bad magic"
   end
   local version = data:byte(4)
   if 1 ~= version then
      return nil, "unsupported version"
   end
   local payload_mac = data:sub(5, 10)
   if "string" == type(src) and 6 == #src and payload_mac ~= src then
      return nil, "MAC mismatch"
   end
   if token and not M.equal(data:sub(11, 14), token) then
      return nil, "token mismatch"
   end
   return {
      mac = M.hex(src or payload_mac),
      version = version,
   }
end

local function u32le(data, offset)
   local a, b, c, d = data:byte(offset, offset + 3)
   if not a then
      return nil
   end
   return a + b * 256 + c * 65536 + d * 16777216
end

local function u16le(data, offset)
   local a, b = data:byte(offset, offset + 1)
   if not a then
      return nil
   end
   return a + b * 256
end

local function i16le(data, offset)
   local value = u16le(data, offset)
   if not value then
      return nil
   end
   if value >= 32768 then
      value = value - 65536
   end
   return value
end

local SENSOR_STATUS = {
   [0] = "ABSENT",
   [1] = "OK",
   [2] = "MISSING",
   [3] = "ERROR",
}

function M.parse_xnw1(data, src)
   if "string" ~= type(data) or 32 ~= #data or "XNW1" ~= data:sub(1, 4) then
      return nil, "bad packet"
   end
   return {
      mac = M.hex(src),
      seq = u32le(data, 5),
      uptime_ms = u32le(data, 9),
   }
end

function M.parse_xnw1_v2(data, src)
   if "string" ~= type(data) or 96 ~= #data or "XNW1" ~= data:sub(1, 4) then
      return nil, "bad packet"
   end
   if 2 ~= data:byte(5) then
      return nil, "unsupported version"
   end
   local slot_count = data:byte(7)
   if not slot_count or slot_count > 5 then
      return nil, "slot_count out of range"
   end
   local sensor_status = SENSOR_STATUS
   local packet = {
      mac = M.hex(src),
      version = 2,
      flags = data:byte(6),
      slot_count = slot_count,
      seq = u32le(data, 9),
      boot_id = u32le(data, 13),
      awake_ms = u32le(data, 17),
      battery_mv = u16le(data, 21),
      chip_temp = i16le(data, 23),
      reset_reason = data:byte(25),
      wake_cause = data:byte(26),
      sensors = {},
   }
   packet.chip_temp_c = nil
   if packet.chip_temp and -32768 ~= packet.chip_temp then
      packet.chip_temp_c = packet.chip_temp / 16
   end
   for i = 0, 4 do
      local offset = 29 + i * 12
      local rom = M.hex(data:sub(offset, offset + 7)):upper()
      local raw = i16le(data, offset + 8)
      local status = data:byte(offset + 10)
      local temp = nil
      if raw and -32768 ~= raw then
         temp = raw / 16
      end
      packet.sensors[#packet.sensors + 1] = {
         index = i,
         rom = rom,
         raw = raw,
         temp = temp,
         status = status,
         status_name = sensor_status[status] or ("UNKNOWN(" .. tostring(status) .. ")"),
         configured = i < slot_count,
         present = "0000000000000000" ~= rom and 0 ~= status,
      }
   end
   return packet
end

function M.magic(data)
   if "string" ~= type(data) or 0 == #data then
      return ""
   end
   local head = data:sub(1, 4)
   if head:match("^%w%w%w%w$") then
      return head
   end
   return (head:sub(1, 3):gsub("[^%w]", "."))
end

function M.new_runtime()
   return {
      open = false,
      channel = nil,
      drops = 0,
      queue_drops = 0,
      last_error = nil,
      nodes = {},
      provision = {
         active = false,
         token = nil,
         until_ms = 0,
         next_ms = 0,
         sent = 0,
         window = 45,
         started_at = 0,
      },
   }
end

function M.ensure_node(runtime, mac)
   mac = M.normalize_mac(mac)
   if not mac then
      return nil
   end
   runtime.nodes = runtime.nodes or {}
   local node = runtime.nodes[mac]
   if node then
      return node
   end
   local count = 0
   for _ in pairs(runtime.nodes) do
      count = count + 1
   end
   if count >= 64 then
      return nil
   end
   node = { mac = mac }
   runtime.nodes[mac] = node
   return node
end

function M.note_packet(runtime, data, src, info, now, token)
   local mac = M.hex(src)
   local node = M.ensure_node(runtime, mac)
   if not node then
      return "ignored"
   end
   info = info or {}
   node.last_seen = now
   node.last_rssi = info.rssi
   node.channel = info.channel
   node.packets = (node.packets or 0) + 1
   node.last_magic = M.magic(data)
   node.last_len = #data

   local pok, pok_err = M.parse_pok(data, src, token)
   if pok then
      node.pok = true
      node.pok_at = now
      node.label = node.label or ""
      return "pok", pok
   end
   if "bad magic" ~= pok_err and "short packet" ~= pok_err then
      node.last_reject = pok_err
      return "reject", pok_err
   end

   local sensor_packet, sensor_err = M.parse_xnw1_v2(data, src)
   if sensor_packet then
      local boot_changed = node.boot_id ~= sensor_packet.boot_id
      local setup = 0 ~= (sensor_packet.flags & 0x01)
      if not boot_changed and node.last_seq and sensor_packet.seq <= node.last_seq then
         node.duplicates = (node.duplicates or 0) + 1
         return "duplicate", sensor_packet
      end
      node.boot_id = sensor_packet.boot_id
      node.last_seq = sensor_packet.seq
      node.flags = sensor_packet.flags
      node.setup = setup
      node.fault = 0 ~= (sensor_packet.flags & 0x02)
      node.low_batt = 0 ~= (sensor_packet.flags & 0x04)
      node.cold_boot = 0 ~= (sensor_packet.flags & 0x08)
      node.awake_ms = sensor_packet.awake_ms
      node.battery_mv = sensor_packet.battery_mv
      node.chip_temp = sensor_packet.chip_temp
      node.chip_temp_c = sensor_packet.chip_temp_c
      node.reset_reason = sensor_packet.reset_reason
      node.wake_cause = sensor_packet.wake_cause
      node.slot_count = sensor_packet.slot_count
      if boot_changed or setup then
         node.sensors = {}
      end
      node.sensors = node.sensors or {}
      for _, sensor in ipairs(sensor_packet.sensors) do
         if sensor.configured and sensor.present then
            node.sensors[sensor.rom] = {
               rom = sensor.rom,
               temp = sensor.temp,
               raw = sensor.raw,
               status = sensor.status,
               status_name = sensor.status_name,
               at = now,
            }
         end
      end
      node.sensor_packet_at = now
      return "sensor", sensor_packet
   end
   if "bad packet" ~= sensor_err and "unsupported version" ~= sensor_err
      and "slot_count out of range" ~= sensor_err then
      node.last_reject = sensor_err
      return "reject", sensor_err
   end

   local xnw1 = M.parse_xnw1(data, src)
   if xnw1 then
      node.xnw1_seq = xnw1.seq
      node.xnw1_uptime_ms = xnw1.uptime_ms
      node.xnw1_at = now
      return "xnw1_v1", xnw1
   end
   return "other"
end

function M.find_node(cfg, mac)
   local key = M.normalize_mac(mac)
   if not key or not cfg.espnow or not cfg.espnow.nodes then
      return nil
   end
   for existing, node in pairs(cfg.espnow.nodes) do
      if M.normalize_mac(existing) == key then
         return node, existing
      end
   end
   return nil
end

function M.add_node(cfg, mac, label)
   mac = M.normalize_mac(mac)
   if not mac then
      return nil, "invalid MAC"
   end
   cfg.espnow = cfg.espnow or {}
   cfg.espnow.nodes = cfg.espnow.nodes or {}
   local existing = M.find_node(cfg, mac)
   if existing then
      return existing
   end
   cfg.espnow.nodes[mac] = { mac = mac, label = tostring(label or "") }
   return cfg.espnow.nodes[mac]
end

function M.remove_node(cfg, mac)
   local key = M.normalize_mac(mac)
   if not key or not cfg.espnow or not cfg.espnow.nodes then
      return false
   end
   local _, existing = M.find_node(cfg, key)
   if not existing then
      return false
   end
   cfg.espnow.nodes[existing] = nil
   return true
end

function M.nodes(runtime, cfg_nodes)
   local list = {}
   local seen = {}
   local function sensor_list(live)
      local sensors = {}
      for _, sensor in pairs(live.sensors or {}) do
         sensors[#sensors + 1] = {
            rom = sensor.rom,
            temp = sensor.temp,
            raw = sensor.raw,
            status = sensor.status,
            status_name = sensor.status_name,
            at = sensor.at,
         }
      end
      table.sort(sensors, function(a, b)
         return a.rom < b.rom
      end)
      return sensors
   end
   local function entry(key, cfg_node, live)
      return {
         mac = key,
         mac_text = M.mac_text(key),
         label = cfg_node and cfg_node.label or "",
         known = cfg_node ~= nil,
         last_seen = live.last_seen,
         last_rssi = live.last_rssi,
         channel = live.channel,
         packets = live.packets or 0,
         duplicates = live.duplicates or 0,
         pok = live.pok or false,
         last_magic = live.last_magic,
         last_len = live.last_len,
         xnw1_seq = live.xnw1_seq,
         xnw1_uptime_ms = live.xnw1_uptime_ms,
         boot_id = live.boot_id,
         last_seq = live.last_seq,
         flags = live.flags,
         setup = live.setup or false,
         fault = live.fault or false,
         low_batt = live.low_batt or false,
         cold_boot = live.cold_boot or false,
         battery_mv = live.battery_mv,
         chip_temp_c = live.chip_temp_c,
         awake_ms = live.awake_ms,
         reset_reason = live.reset_reason,
         wake_cause = live.wake_cause,
         slot_count = live.slot_count,
         sensors = sensor_list(live),
      }
   end
   for mac, cfg_node in pairs(cfg_nodes or {}) do
      local key = M.normalize_mac(mac)
      if key then
         seen[key] = true
         local live = runtime.nodes and runtime.nodes[key] or {}
         list[#list + 1] = entry(key, cfg_node, live)
      end
   end
   for mac, live in pairs(runtime.nodes or {}) do
      if not seen[mac] then
         list[#list + 1] = entry(mac, nil, live)
      end
   end
   table.sort(list, function(a, b)
      return a.mac < b.mac
   end)
   return list
end

return M
