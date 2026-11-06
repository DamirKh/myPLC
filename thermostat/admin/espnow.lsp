<?lsp
if not app.pin_guard(request, response, "/admin/espnow.lsp") then
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
      message = "Запрос отклонён: неверный CSRF-токен."
      message_kind = "error"
   end
   local origin = request:header("Origin")
   local host = request:header("Host")
   if origin and host and not origin:find(host, 1, true) then
      csrf_ok = false
      message = "Запрос отклонён: неверный Origin."
      message_kind = "error"
   end
end

local function error_text(err)
   if "table" == type(err) then
      return table.concat(err, "; ")
   end
   return tostring(err)
end

if "POST" == request:method() and csrf_ok then
   local action = request:data("action")
   if "start" == action then
      local ok, err = app.espnow_start_provision()
      if ok then
         message = "Окно провижининга запущено."
      else
         message = "Ошибка: " .. error_text(err)
         message_kind = "error"
      end
   elseif "stop" == action then
      local ok, was = app.espnow_stop_provision()
      if ok and was then
         message = "Окно провижининга остановлено. Приёмник остаётся включённым."
      else
         message = "Окно провижининга уже неактивно."
      end
   elseif "disable" == action then
      local ok, err = app.espnow_disable()
      if ok then
         message = "Приёмник ESP-NOW выключен."
      else
         message = "Ошибка: " .. error_text(err)
         message_kind = "error"
      end
   elseif "forget" == action then
      local ok, err = app.espnow_forget_node(request:data("mac"))
      if ok then
         message = "Узел удалён из конфигурации."
      else
         message = "Ошибка: " .. error_text(err)
         message_kind = "error"
      end
   end
end

local function esc(value)
   return tostring(value or "")
      :gsub("&", "&amp;")
      :gsub("<", "&lt;")
      :gsub(">", "&gt;")
      :gsub('"', "&quot;")
end

local function feedback_html(text, kind, oob)
   local body = ""
   if text then
      body = '<section class="banner ' .. esc(kind or "ok") .. '">' .. esc(text) .. "</section>"
   end
   local attr = oob and ' hx-swap-oob="true"' or ""
   return '<div id="espnow-feedback"' .. attr .. ">" .. body .. "</div>"
end

local function mode_text(st)
   local mode = st.wifi_mode or "—"
   if "sta" == mode then
      return st.wifi_connected and "STA, подключено" or "STA, нет подключения"
   elseif "ap" == mode then
      return st.ready and "AP, активно" or "AP"
   end
   return mode
end

local function status_html(oob)
   local st = app.espnow_status()
   local attr = oob and ' hx-swap-oob="true"' or ""
   local poll_interval = st.provision_active and "1s" or (st.open and "3s" or "10s")
   local out = {
      '<section id="espnow-status" class="card"' .. attr,
      ' hx-get="/admin/espnow.lsp?fragment=status" hx-trigger="every ' .. poll_interval .. '" hx-swap="outerHTML">',
      "<h2>ESP-NOW</h2>",
      "<p>API: <strong>" .. (st.available and "доступен" or "недоступен") .. "</strong></p>",
      "<p>Приёмник: <strong>" .. (st.open and "открыт" or "закрыт") .. "</strong>"
         .. (st.enabled and " (включён в конфиге)" or " (выключен в конфиге)") .. "</p>",
      "<p>Wi-Fi: <strong>" .. esc(mode_text(st)) .. "</strong></p>",
      "<p>Канал: <strong>" .. esc(st.channel or "—") .. "</strong></p>",
   }
   if st.provision_active then
      out[#out + 1] = "<p>Провижининг: <strong>активен</strong>, осталось "
         .. tostring(st.provision_remaining) .. " с, отправлено PROV: "
         .. tostring(st.provision_sent) .. "</p>"
      if st.token_hex then
         out[#out + 1] = '<p class="muted">Token: <code>' .. esc(st.token_hex) .. "</code></p>"
      end
   else
      out[#out + 1] = "<p>Провижининг: <strong>неактивен</strong></p>"
   end
   out[#out + 1] = "<p>Пакетов отброшено: API " .. tostring(st.drops or 0)
      .. ", очередь " .. tostring(st.queue_drops or 0) .. "</p>"
   if st.last_error then
      out[#out + 1] = '<p class="banner error">Последняя ошибка: ' .. esc(st.last_error) .. "</p>"
   end
   if st.available then
      out[#out + 1] = '<div class="row" style="margin-top:16px">'
      if st.provision_active then
         out[#out + 1] = '<form method="post" class="inline" action="/admin/espnow.lsp?fragment=status"'
            .. ' hx-post="/admin/espnow.lsp?fragment=status" hx-target="#espnow-status" hx-swap="outerHTML">'
            .. '<input type="hidden" name="csrf" value="' .. esc(app.csrf_token()) .. '">'
            .. '<input type="hidden" name="action" value="stop">'
            .. '<button type="submit" class="secondary">Остановить провижининг</button></form>'
      else
         local disabled = st.ready and "" or " disabled"
         out[#out + 1] = '<form method="post" class="inline" action="/admin/espnow.lsp?fragment=status"'
            .. ' hx-post="/admin/espnow.lsp?fragment=status" hx-target="#espnow-status" hx-swap="outerHTML">'
            .. '<input type="hidden" name="csrf" value="' .. esc(app.csrf_token()) .. '">'
            .. '<input type="hidden" name="action" value="start">'
            .. '<button type="submit"' .. disabled .. '>Начать провижининг</button></form>'
      end
      if st.open or st.enabled then
         out[#out + 1] = '<form method="post" class="inline" action="/admin/espnow.lsp?fragment=status"'
            .. ' hx-post="/admin/espnow.lsp?fragment=status" hx-target="#espnow-status" hx-swap="outerHTML"'
            .. ' hx-confirm="Выключить приёмник ESP-NOW?">'
            .. '<input type="hidden" name="csrf" value="' .. esc(app.csrf_token()) .. '">'
            .. '<input type="hidden" name="action" value="disable">'
            .. '<button type="submit" class="secondary">Выключить приёмник</button></form>'
      end
      out[#out + 1] = "</div>"
   end

   local nodes = st.nodes or {}
   out[#out + 1] = '<h3 style="margin-top:24px">Узлы</h3>'
   if 0 == #nodes then
      out[#out + 1] = '<p class="muted">Узлы не найдены. Запустите провижининг и переведите узел в provisioning mode.</p>'
   else
      out[#out + 1] = '<div class="table-wrap"><table>'
      out[#out + 1] = "<thead><tr><th>MAC</th><th>Метка</th><th>RSSI</th><th>Канал</th>"
         .. "<th>Последний пакет</th><th>Пакетов</th><th>POK</th><th>XNW1</th><th>Allowlist</th><th></th></tr></thead><tbody>"
      local now = os.time()
      for _, node in ipairs(nodes) do
         local age = node.last_seen and (now - node.last_seen) or nil
         local seen = age and (tostring(age) .. " с назад") or "—"
         local packet = node.last_magic and (esc(node.last_magic) .. " / " .. tostring(node.last_len or 0) .. " Б") or "—"
         local xnw1 = node.xnw1_seq and ("seq " .. tostring(node.xnw1_seq)) or "—"
         out[#out + 1] = "<tr><td><code>" .. esc(node.mac_text or node.mac) .. "</code></td><td>"
            .. esc(node.label or "") .. "</td><td>"
            .. (node.last_rssi and (tostring(node.last_rssi) .. " dBm") or "—") .. "</td><td>"
            .. esc(node.channel or "—") .. "</td><td>" .. seen .. "</td><td>"
            .. tostring(node.packets or 0) .. "</td><td>" .. (node.pok and "да" or "нет")
            .. "</td><td>" .. esc(xnw1) .. "</td><td>" .. (node.known and "да" or "нет") .. "</td><td>"
         if node.known then
            out[#out + 1] = '<form method="post" class="inline" action="/admin/espnow.lsp?fragment=status"'
               .. ' hx-post="/admin/espnow.lsp?fragment=status" hx-target="#espnow-status" hx-swap="outerHTML"'
               .. ' hx-confirm="Удалить узел ' .. esc(node.mac_text or node.mac) .. ' из конфигурации?">'
               .. '<input type="hidden" name="csrf" value="' .. esc(app.csrf_token()) .. '">'
               .. '<input type="hidden" name="action" value="forget">'
               .. '<input type="hidden" name="mac" value="' .. esc(node.mac) .. '">'
               .. '<button type="submit" class="secondary">Забыть</button></form>'
         end
         out[#out + 1] = "</td></tr>"
      end
      out[#out + 1] = "</tbody></table></div>"
   end
   out[#out + 1] = "</section>"
   return table.concat(out)
end

local function instructions_html()
   return [[
<section class="card">
  <h2>Как провижинить узел</h2>
  <ol>
    <li>Переведите узел в provisioning mode: без сохранённого конфига или с GPIO4 на GND при старте.</li>
    <li>Запустите окно провижининга. Контроллер 45 секунд рассылает <code>PROV</code> каждые 100 мс.</li>
    <li>После <code>POK</code> MAC узла сохраняется в конфигурации; приёмник остаётся включённым.</li>
  </ol>
  <p class="muted">В STA канал следует за точкой доступа; в AP используется канал 1. При смене канала узлы могут потерять связь. Token — только признак совпадения, не аутентификация; допуск узлов задаётся allowlist MAC.</p>
  <p class="muted">Передача DS18B20-температур по ESP-NOW будет отдельным этапом.</p>
</section>
]]
end

if is_htmx then
   response:setheader("Content-Type", "text/html; charset=utf-8")
   response:setheader("Cache-Control", "no-store")
   response:write(status_html(false))
   if "POST" == request:method() and message then
      response:write(feedback_html(message, message_kind, true))
   end
   return
end
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ESP-NOW — тёплый пол</title>
<script src="/static/theme.js"></script>
<script src="/static/htmx.min.js" defer></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=14">
</head>
<body>
<main>
<?lsp=app.ui_header{title="ESP-NOW", subtitle="Провижининг узлов", active="settings"}?>
<?lsp=app.ui_settings_tabs("espnow")?>

<?lsp=feedback_html(message, message_kind, false)?>
<?lsp=status_html(false)?>
<?lsp=instructions_html()?>
</main>
</body>
</html>
