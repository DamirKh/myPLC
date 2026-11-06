local M = {}

local function esc(value)
   return tostring(value or "")
      :gsub("&", "&amp;")
      :gsub("<", "&lt;")
      :gsub(">", "&gt;")
      :gsub('"', "&quot;")
end

local function nav_item(href, label, active)
   local attr = active and ' class="active" aria-current="page"' or ""
   return '<a href="' .. href .. '"' .. attr .. ">" .. label .. "</a>"
end

local theme_button = [[
<button id="themeToggle" class="theme-toggle" type="button" aria-label="Включить тёмную тему" title="Включить тёмную тему">
  <svg class="icon theme-icon-sun" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/></svg>
  <svg class="icon theme-icon-moon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 15.5A8.5 8.5 0 0 1 8.5 4 8.5 8.5 0 1 0 20 15.5z"/></svg>
</button>
]]

function M.header(opts)
   opts = opts or {}
   local active = opts.active
   local actions = opts.actions or ""
   local theme = opts.theme ~= false and theme_button or ""
   local title = esc(opts.title or "Тёплый пол")
   local subtitle = ""
   if opts.subtitle and "" ~= opts.subtitle then
      subtitle = '<p class="muted full-only">' .. esc(opts.subtitle) .. "</p>"
   end
   return "<header>"
      .. "<div><h1>" .. title .. "</h1>" .. subtitle .. "</div>"
      .. '<div class="header-actions">'
      .. '<nav class="primary-nav" aria-label="Основная навигация">'
      .. nav_item("/", "Обзор", active == "overview")
      .. nav_item("/history.lsp", "История", active == "history")
      .. nav_item("/admin/settings.lsp", "Настройки", active == "settings")
      .. "</nav>"
      .. actions
      .. theme
      .. "</div></header>"
end

function M.settings_tabs(active)
   return '<nav class="subnav" aria-label="Настройки">'
      .. nav_item("/admin/settings.lsp", "Основные", active == "general")
      .. nav_item("/admin/sensors.lsp", "Сервис", active == "service")
      .. nav_item("/admin/wifi.lsp", "Wi-Fi", active == "wifi")
      .. nav_item("/admin/espnow.lsp", "ESP-NOW", active == "espnow")
      .. nav_item("/admin/pin.lsp", "PIN", active == "pin")
      .. '<a class="subnav-action" href="/admin/lock.lsp">Заблокировать</a>'
      .. "</nav>"
end

return M
