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

function M.parse_xnw1(data, src)
   if "string" ~= type(data) or #data < 12 or "XNW1" ~= data:sub(1, 4) then
      return nil, "bad packet"
   end
   return {
      mac = M.hex(src),
      seq = u32le(data, 5),
      uptime_ms = u32le(data, 9),
   }
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

   local xnw1 = M.parse_xnw1(data, src)
   if xnw1 then
      node.xnw1_seq = xnw1.seq
      node.xnw1_uptime_ms = xnw1.uptime_ms
      node.xnw1_at = now
      return "xnw1", xnw1
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
   for mac, cfg_node in pairs(cfg_nodes or {}) do
      local key = M.normalize_mac(mac)
      if key then
         seen[key] = true
         local live = runtime.nodes and runtime.nodes[key] or {}
         list[#list + 1] = {
            mac = key,
            mac_text = M.mac_text(key),
            label = cfg_node.label or "",
            known = true,
            last_seen = live.last_seen,
            last_rssi = live.last_rssi,
            channel = live.channel,
            packets = live.packets or 0,
            pok = live.pok or false,
            last_magic = live.last_magic,
            last_len = live.last_len,
            xnw1_seq = live.xnw1_seq,
            xnw1_uptime_ms = live.xnw1_uptime_ms,
         }
      end
   end
   for mac, live in pairs(runtime.nodes or {}) do
      if not seen[mac] then
         list[#list + 1] = {
            mac = mac,
            mac_text = M.mac_text(mac),
            label = "",
            known = false,
            last_seen = live.last_seen,
            last_rssi = live.last_rssi,
            channel = live.channel,
            packets = live.packets or 0,
            pok = live.pok or false,
            last_magic = live.last_magic,
            last_len = live.last_len,
            xnw1_seq = live.xnw1_seq,
            xnw1_uptime_ms = live.xnw1_uptime_ms,
         }
      end
   end
   table.sort(list, function(a, b)
      return a.mac < b.mac
   end)
   return list
end

return M
