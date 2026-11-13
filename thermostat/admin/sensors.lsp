<?lsp
if not app.pin_guard(request, response, "/admin/sensors.lsp") then
   return
end

local message = nil
local message_kind = "ok"
local csrf_ok = true
local is_htmx = app.htmx_request(request)
local fragment = request:data("fragment")

if "POST" == request:method() then
   if not app.csrf_valid(request:data("csrf")) then
      csrf_ok = false
      message = "Запрос отклонён: неверный CSRF-токен"
      message_kind = "error"
   end
end

local function parse_rows()
   local payload = request:data("payload")
   if payload and "" ~= payload then
      local decoded, rows = pcall(ba.json.decode, payload)
      if decoded and "table" == type(rows) then
         return rows
      end
   end
   local count = tonumber(request:data("row_count")) or 0
   local rows = {}
   for i = 1, count do
      local bus = request:data("row_" .. i .. "_bus")
      local rom = request:data("row_" .. i .. "_rom")
      if bus and rom then
         rows[#rows + 1] = {
            bus = bus,
            rom = rom,
            role = request:data("row_" .. i .. "_role") or "",
            label = request:data("row_" .. i .. "_label") or "",
            offset = request:data("row_" .. i .. "_offset") or "0",
         }
      end
   end
   return rows
end

if "POST" == request:method() and csrf_ok then
   local action = request:data("action")
   if "service" == action then
      local on = "on" == request:data("state")
      app.set_service_mode(on)
      message = on and "Сервисный режим включён. Насос выключен, идёт поиск датчиков."
         or "Сервисный режим выключен."
   elseif "scan" == action then
      local result = app.scan_sensors()
      local status = result and result.status or "queued"
      message = ("running" == status) and "Сканирование уже выполняется" or "Сканирование запущено"
   elseif "reset_hours" == action then
      local ok = app.reset_pump_hours()
      if ok then
         message = "Моточасы насоса сброшены."
      else
         message = "Не удалось сбросить моточасы."
         message_kind = "error"
      end
   elseif "apply" == action then
      local rows = parse_rows()
      local ok = app.update_sensors(rows)
      if ok then
         message = "Изменения применены."
      else
         message = "Не удалось применить изменения. Проверьте роли, ROM и конфигурацию."
         message_kind = "error"
      end
   elseif "assign" == action then
      local role = request:data("role")
      local bus = request:data("bus")
      local rom = request:data("rom")
      local ok
      if not role or "" == role or "none" == role then
         ok = app.remove_sensor(bus, rom)
      else
         ok = app.assign_sensor(bus, rom, role, request:data("label"), tonumber(request:data("offset")))
      end
      if ok then
         message = "Изменения применены."
      else
         message = "Не удалось применить изменения. Проверьте роли, ROM и конфигурацию."
         message_kind = "error"
      end
   end
   if not is_htmx and csrf_ok and message then
      local suffix = "saved=1"
      if "service" == action then
         suffix = "service=" .. ("on" == request:data("state") and "on" or "off")
      elseif "scan" == action then
         suffix = "scan=queued"
      elseif "reset_hours" == action then
         suffix = message_kind == "error" and "err=hours" or "hours=1"
      elseif "apply" == action or "assign" == action then
         suffix = message_kind == "error" and "err=apply" or "saved=1"
      end
      response:sendredirect("/admin/sensors.lsp?" .. suffix)
      return
   end
end

local service_note = request:data("service")
if "on" == service_note then
   message = "Сервисный режим включён. Насос выключен, идёт поиск датчиков."
elseif "off" == service_note then
   message = "Сервисный режим выключен."
end
local scan_note = request:data("scan")
if scan_note then
   message = ("running" == scan_note) and "Сканирование уже выполняется" or "Сканирование запущено"
end
if "1" == request:data("saved") then
   message = "Изменения применены."
elseif "1" == request:data("hours") then
   message = "Моточасы насоса сброшены."
elseif request:data("err") then
   message = "Не удалось применить изменения. Проверьте роли, ROM и конфигурацию."
   message_kind = "error"
end

local service = app.service_mode_enabled()
local sensor_table = app.get_sensor_table()
local pump_hours = app.get_state().pump_hours
local scan_active = sensor_table.scan_active and true or false
local roles = {
   { "", "не назначена" },
   { "room", "room — воздух" },
   { "floor", "floor — пол" },
   { "supply", "supply — подача" },
   { "return", "return — обратка" },
   { "pump", "pump — насос" },
   { "extra", "extra — прочее" },
}

local function esc(text)
   return tostring(text or "")
      :gsub("&", "&amp;")
      :gsub('"', "&quot;")
      :gsub("<", "&lt;")
      :gsub(">", "&gt;")
end

local function fmt_temp(temp)
   if "number" == type(temp) then
      return string.format("%.2f °C", temp)
   end
   return "—"
end

local function status_text(item)
   if item.ok then
      return "OK"
   end
   local err = item.err
   if "not_found" == err then
      return "не найден"
   elseif "not_read" == err then
      return "нет данных"
   elseif "no presence" == err then
      return "нет связи"
   elseif "missing" == err then
      return "не найден"
   elseif "error" == err then
      return "ошибка"
   elseif "absent" == err then
      return "нет в пакете"
   elseif "invalid_temperature" == err then
      return "нет температуры"
   elseif "invalid_status" == err then
      return "неизвестный статус"
   elseif "CRC error" == err then
      return "ошибка CRC"
   elseif "timeout" == err then
      return "таймаут"
   elseif "power_on_reset_85C" == err then
      return "85 °C после включения"
   end
   return err or "—"
end

local function role_options(selected)
   local out = {}
   for _, role in ipairs(roles) do
      out[#out + 1] = '<option value="' .. role[1] .. '"'
         .. ((selected or "") == role[1] and " selected" or "")
         .. ">" .. role[2] .. "</option>"
   end
   return table.concat(out)
end

local function feedback_html(text, kind, oob)
   local body = ""
   if text then
      body = '<section class="banner ' .. esc(kind or "ok") .. '">' .. esc(text) .. "</section>"
   end
   local attr = oob and ' hx-swap-oob="true"' or ""
   return '<div id="sensor-feedback"' .. attr .. ">" .. body .. "</div>"
end

local function service_html()
   local poll = ""
   if service or scan_active then
      poll = ' hx-get="/admin/sensors.lsp?fragment=service" hx-trigger="every 2s" hx-swap="outerHTML"'
   end
   local out = {
      '<section id="service-panel" class="card"' .. poll .. ">",
      '<div class="service-head">',
      "<div><h2>Сервисный режим</h2>",
      '<p class="muted">Насос выключен, датчики читаются часто. Роли и параметры можно менять только здесь.</p></div>',
      '<div class="service-actions">',
      '<span class="service-state ' .. (service and "on" or "off") .. '">' .. (service and "включён" or "выключен") .. "</span>",
      '<form method="post" class="inline" action="/admin/sensors.lsp?fragment=service"',
      ' hx-post="/admin/sensors.lsp?fragment=service" hx-target="#service-panel" hx-swap="outerHTML">',
      '<input type="hidden" name="csrf" value="' .. esc(app.csrf_token()) .. '">',
      '<input type="hidden" name="action" value="service">',
      '<input type="hidden" name="state" value="' .. (service and "off" or "on") .. '">',
      '<button type="submit" class="' .. (service and "secondary" or "") .. '">'
         .. (service and "Выключить сервисный режим" or "Включить сервисный режим") .. "</button>",
      "</form></div></div>",
   }
   if service then
      out[#out + 1] = '<div class="row" style="margin-top:16px">'
      out[#out + 1] = '<form method="post" class="inline" action="/admin/sensors.lsp?fragment=service"'
         .. ' hx-post="/admin/sensors.lsp?fragment=service" hx-target="#service-panel" hx-swap="outerHTML">'
         .. '<input type="hidden" name="csrf" value="' .. esc(app.csrf_token()) .. '">'
         .. '<input type="hidden" name="action" value="scan">'
         .. '<button type="submit" class="secondary">Пересканировать шины</button></form>'
      out[#out + 1] = '<form method="post" class="inline" action="/admin/sensors.lsp?fragment=service"'
         .. ' hx-post="/admin/sensors.lsp?fragment=service" hx-target="#service-panel" hx-swap="outerHTML"'
         .. ' hx-confirm="Сбросить моточасы насоса?">'
         .. '<input type="hidden" name="csrf" value="' .. esc(app.csrf_token()) .. '">'
         .. '<input type="hidden" name="action" value="reset_hours">'
         .. '<button type="submit" class="secondary">Сбросить моточасы</button></form>'
      out[#out + 1] = '<span class="muted">Моточасы: '
         .. (("number" == type(pump_hours)) and string.format("%.1f ч", pump_hours) or "—") .. "</span>"
      if scan_active then
         out[#out + 1] = '<span class="muted">Идёт сканирование…</span>'
      end
      out[#out + 1] = "</div>"
   end
   out[#out + 1] = "</section>"
   return table.concat(out)
end

local function table_html(oob)
   local total = 0
   for _, bus in ipairs(sensor_table.buses or {}) do
      total = total + #(bus.sensors or {})
   end
   local interval = service and "2s" or "10s"
   local attr = oob and ' hx-swap-oob="true"' or ""
   local out = {
      '<section id="sensor-table" class="card"' .. attr .. ">",
      "<h2>Датчики</h2>",
      '<div id="sensor-values-poller" hx-get="/admin/sensors.lsp?fragment=values" hx-trigger="every '
         .. interval .. '" hx-swap="none"></div>',
   }
   if not service then
      out[#out + 1] = '<p class="banner">Включите сервисный режим, чтобы менять роли, метки и смещения.</p>'
   end
   out[#out + 1] = '<form id="sensor-form" method="post" action="/admin/sensors.lsp?fragment=table"'
      .. ' hx-post="/admin/sensors.lsp?fragment=table" hx-target="#sensor-table" hx-swap="outerHTML">'
      .. '<input type="hidden" name="csrf" value="' .. esc(app.csrf_token()) .. '">'
      .. '<input type="hidden" name="action" value="apply">'
      .. '<input type="hidden" name="row_count" value="' .. tostring(total) .. '">'
      .. '<input type="hidden" name="payload" id="sensor-payload" value="">'
      .. '<div class="table-wrap"><table class="sensor-table">'
      .. "<thead><tr><th>ROM</th><th>Температура</th><th>Статус</th><th>Роль</th><th>Метка</th><th>Смещение</th></tr></thead>"
   local index = 0
   for _, bus in ipairs(sensor_table.buses or {}) do
      out[#out + 1] = '<tbody><tr class="bus-row"><th colspan="6">Шина <code>' .. esc(bus.name)
         .. "</code> · " .. (bus.espnow and ("ESP-NOW " .. esc(bus.mac)) or ("GPIO " .. esc(bus.pin)))
         .. " · датчиков: " .. tostring(#(bus.sensors or {})) .. "</th></tr>"
      if 0 == #(bus.sensors or {}) then
         out[#out + 1] = '<tr><td colspan="6" class="muted">Датчики не найдены</td></tr>'
      end
      for _, sensor in ipairs(bus.sensors or {}) do
         index = index + 1
         local prefix = "row_" .. index .. "_"
         out[#out + 1] = '<tr data-key="' .. esc(sensor.key) .. '" data-bus="' .. esc(bus.name)
            .. '" data-rom="' .. esc(sensor.rom) .. '">'
         out[#out + 1] = '<td><input type="hidden" name="' .. prefix .. 'bus" value="' .. esc(bus.name)
            .. '"><input type="hidden" name="' .. prefix .. 'rom" value="' .. esc(sensor.rom)
            .. '"><code class="sensor-rom">' .. esc(sensor.rom) .. "</code></td>"
         out[#out + 1] = '<td class="sensor-temp"><span id="sensor-temp-' .. index
            .. '" data-temp>' .. fmt_temp(sensor.temp)
            .. '</span><span id="sensor-rise-' .. index .. '" class="rise-icon" data-rise title="'
            .. (sensor.rise_top and "Максимальный рост температуры" or "") .. '">'
            .. (sensor.rise_top and "↑" or "") .. "</span></td>"
         out[#out + 1] = '<td><span id="sensor-status-' .. index .. '" class="sensor-status '
            .. (sensor.ok and "ok" or "error") .. '" data-status>' .. esc(status_text(sensor)) .. "</span></td>"
         out[#out + 1] = '<td><select name="' .. prefix .. 'role" data-field="role"'
            .. (not service and " disabled" or "") .. ">" .. role_options(sensor.role) .. "</select></td>"
         out[#out + 1] = '<td><input name="' .. prefix .. 'label" data-field="label" class="sensor-label-input" value="'
            .. esc(sensor.label) .. '"' .. (not service and " disabled" or "") .. "></td>"
         out[#out + 1] = '<td><input name="' .. prefix .. 'offset" data-field="offset" class="sensor-offset-input" type="number" step="0.1" value="'
            .. esc(string.format("%.1f", sensor.offset or 0)) .. '"' .. (not service and " disabled" or "") .. "></td>"
         out[#out + 1] = "</tr>"
      end
      out[#out + 1] = "</tbody>"
   end
   out[#out + 1] = "</table></div>"
   if service then
      out[#out + 1] = '<div class="row sensor-actions"><button type="submit">Применить</button>'
         .. '<button type="reset" class="secondary">Отмена</button></div>'
   end
   out[#out + 1] = "</form></section>"
   return table.concat(out)
end

local function values_html()
   local out = {}
   local index = 0
   for _, bus in ipairs(sensor_table.buses or {}) do
      for _, sensor in ipairs(bus.sensors or {}) do
         index = index + 1
         out[#out + 1] = '<span id="sensor-temp-' .. index
            .. '" data-temp hx-swap-oob="outerHTML">' .. fmt_temp(sensor.temp) .. "</span>"
         out[#out + 1] = '<span id="sensor-status-' .. index .. '" class="sensor-status '
            .. (sensor.ok and "ok" or "error") .. '" data-status hx-swap-oob="outerHTML">'
            .. esc(status_text(sensor)) .. "</span>"
         out[#out + 1] = '<span id="sensor-rise-' .. index .. '" class="rise-icon" data-rise title="'
            .. (sensor.rise_top and "Максимальный рост температуры" or "")
            .. '" hx-swap-oob="outerHTML">' .. (sensor.rise_top and "↑" or "") .. "</span>"
      end
   end
   return table.concat(out)
end

if is_htmx then
   response:setheader("Content-Type", "text/html; charset=utf-8")
   response:setheader("Cache-Control", "no-store")
   if "service" == fragment then
      response:write(service_html())
      if "POST" == request:method() then
         response:write(table_html(true))
         if message then
            response:write(feedback_html(message, message_kind, true))
         end
      end
   elseif "table" == fragment then
      response:write(table_html(false))
      if message then
         response:write(feedback_html(message, message_kind, true))
      end
   elseif "values" == fragment then
      response:write(values_html())
   else
      response:write(service_html())
      response:write(table_html(false))
      if message then
         response:write(feedback_html(message, message_kind, true))
      end
   end
   return
end
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Сервис — тёплый пол</title>
<script src="/static/theme.js"></script>
<script src="/static/htmx.min.js" defer></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=14">
</head>
<body>
<main>
<?lsp=app.ui_header{title="Сервис", subtitle="Датчики, роли и сервисный режим", active="settings"}?>
<?lsp=app.ui_settings_tabs("service")?>

<?lsp=feedback_html(message, message_kind, false)?>
<?lsp=service_html()?>
<?lsp=table_html(false)?>
</main>
</body>
</html>
