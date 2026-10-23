local M = {}

function M.jumper_closed(level)
   if "boolean" == type(level) then
      return not level
   end
   if "number" == type(level) then
      return 0 == level
   end
   return nil
end

function M.sta_configured(cfg)
   local wifi = cfg and cfg.wifi or {}
   return "string" == type(wifi.sta_ssid)
      and "string" == type(wifi.sta_password_enc)
      and "" ~= wifi.sta_ssid
      and "" ~= wifi.sta_password_enc
end

function M.desired(cfg, jumper_closed, ap_latched)
   local wifi = cfg and cfg.wifi or {}
   if jumper_closed or ap_latched then
      return "ap", "jumper"
   end
   if "ap" == wifi.mode then
      return "ap", "manual"
   end
   if not M.sta_configured(cfg) then
      return "ap", "unconfigured"
   end
   return "sta", wifi.sta_confirmed and "confirmed" or "unconfirmed"
end

function M.should_fallback(cfg)
   local wifi = cfg and cfg.wifi or {}
   return not (wifi.sta_confirmed and true or false)
end

return M
