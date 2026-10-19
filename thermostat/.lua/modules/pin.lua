local M = {}

function M.validate(pin)
   pin = tostring(pin or "")
   return 4 == #pin and pin:match("^%d%d%d%d$") ~= nil
end

function M.hex(data)
   return (tostring(data or ""):gsub(".", function(c)
      return string.format("%02x", c:byte())
   end))
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

function M.random_salt()
   if not (ba and ba.aeskey) then
      return nil, "RNG unavailable"
   end
   local ok, key = pcall(ba.aeskey, 16)
   if not ok or not key then
      return nil, tostring(key)
   end
   return M.hex(key)
end

function M.hash(pin, salt, iterations)
   if not (ba and ba.crypto and ba.crypto.PBKDF2) then
      return nil, "PBKDF2 unavailable"
   end
   local ok, raw = pcall(ba.crypto.PBKDF2, "sha256", tostring(pin), tostring(salt), iterations or 20000, 32)
   if not ok or not raw then
      return nil, tostring(raw)
   end
   return M.hex(raw)
end

function M.verify(pin, security)
   if not M.validate(pin) or "table" ~= type(security) then
      return false
   end
   if not security.pin_hash or "" == security.pin_hash or not security.pin_salt then
      return false
   end
   local hash = M.hash(pin, security.pin_salt, security.pin_iterations or 20000)
   return hash and M.equal(hash, security.pin_hash) or false
end

local function ipv4_parts(ip)
   local a, b, c = tostring(ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.")
   if not a then
      return nil
   end
   return tonumber(a), tonumber(b), tonumber(c)
end

local function ipv6_parts(ip)
   local text = tostring(ip or ""):lower()
   if not text:find(":", 1, true) then
      return nil
   end
   local groups = {}
   for group in text:gmatch("[^:]+") do
      groups[#groups + 1] = group
   end
   return groups
end

function M.is_trusted(peer, server)
   peer, server = tostring(peer or ""), tostring(server or "")
   if "127.0.0.1" == peer or "::1" == peer then
      return true
   end
   local pa, pb, pc = ipv4_parts(peer)
   local sa, sb, sc = ipv4_parts(server)
   if pa and sa then
      return pa == sa and pb == sb and pc == sc
   end
   local pg = ipv6_parts(peer)
   local sg = ipv6_parts(server)
   if pg and sg and #pg >= 4 and #sg >= 4 then
      for i = 1, 4 do
         if pg[i] ~= sg[i] then
            return false
         end
      end
      return true
   end
   return false
end

return M
