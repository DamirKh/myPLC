<?lsp
if not app.pin_guard(request, response, "/admin/wifi.lsp") then
   return
end

local message = nil
local message_kind = "ok"
local scan = nil
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
   if "scan" == action then
      local result, err = app.wifi_scan()
      if result then
         scan = result
         if #result > 0 then
            message = "Найдено сетей: " .. tostring(#result)
         else
            message = "Сканирование вернуло 0 сетей. Введите SSID вручную."
            message_kind = ""
         end
      else
         message = "Ошибка сканирования: " .. error_text(err)
         message_kind = "error"
      end
   elseif "connect" == action then
      local ok, result = app.wifi_connect(request:data("ssid"), request:data("pwd"))
      if ok then
         if result.deferred then
            message = "Сеть «" .. tostring(result.ssid) .. "» сохранена. Джампер AP замкнут, устройство остаётся в AP."
         else
            message = "Подключение к «" .. tostring(result.ssid) .. "» запущено. Устройство переключится через 2 секунды."
         end
      else
         message = "Ошибка: " .. error_text(result)
         message_kind = "error"
      end
   elseif "sta" == action then
      local ok, result = app.wifi_use_saved()
      if ok then
         message = "Подключение к сохранённой сети «" .. tostring(result.ssid) .. "» запущено."
      else
         message = "Ошибка: " .. error_text(result)
         message_kind = "error"
      end
   elseif "ap" == action then
      local ok, result = app.wifi_switch_ap()
      if ok then
         message = "Переключение в AP запущено. Подключитесь к сети xedge32 и откройте http://192.168.190.0/."
      else
         message = "Ошибка: " .. error_text(result)
         message_kind = "error"
      end
   elseif "forget" == action then
      local ok, result = app.wifi_forget()
      if ok then
         message = "Сохранённая сеть удалена. Устройство переключается в AP."
      else
         message = "Ошибка: " .. error_text(result)
         message_kind = "error"
      end
   end
end

local st = app.get_state()
local pick = request:data("pick") or st.wifi_sta_ssid or ""
local has_credentials = st.wifi_has_credentials and true or false

local function esc(value)
   return tostring(value or "")
      :gsub("&", "&amp;")
      :gsub("<", "&lt;")
      :gsub(">", "&gt;")
      :gsub('"', "&quot;")
end

local function mode_text()
   local text = st.wifi_mode or "—"
   if "sta" == text then
      text = st.wifi_sta_connected and "STA, подключено" or "STA, нет подключения"
   elseif "ap" == text then
      text = "AP"
   end
   return text
end

local function jumper_text()
   if not st.ap_jumper_available then
      return "недоступен"
   end
   if true == st.ap_jumper_closed then
      return "замкнут"
   end
   if false == st.ap_jumper_closed then
      return "разомкнут"
   end
   return "неизвестно"
end

local function feedback_html(text, kind, oob)
   local body = ""
   if text then
      body = '<section class="banner ' .. esc(kind or "ok") .. '">' .. esc(text) .. "</section>"
   end
   local attr = oob and ' hx-swap-oob="true"' or ""
   return '<div id="wifi-feedback"' .. attr .. ">" .. body .. "</div>"
end

local function status_html(oob)
   local attr = oob and ' hx-swap-oob="true"' or ""
   local out = {
      '<section id="wifi-status" class="card"' .. attr,
      ' hx-get="/admin/wifi.lsp?fragment=status" hx-trigger="every 5s" hx-swap="outerHTML">',
      "<h2>Текущее состояние</h2>",
      "<p>Режим: <strong>" .. esc(mode_text()) .. "</strong></p>",
      "<p>Джампер AP: <strong>" .. esc(jumper_text()) .. "</strong></p>",
      "<p>STA подтверждён: <strong>" .. (st.wifi_sta_confirmed and "да" or "нет") .. "</strong></p>",
   }
   if st.ap_jumper_latched and not st.ap_jumper_closed then
      out[#out + 1] = '<p class="banner">AP удерживается после снятия джампера до перезагрузки или ручного переключения в STA.</p>'
   end
   if st.ap_jumper_error then
      out[#out + 1] = '<p class="banner error">Джампер AP: ' .. esc(st.ap_jumper_error) .. "</p>"
   end
   out[#out + 1] = "<p>IP: <strong>" .. esc(st.wifi_ip or "—") .. "</strong></p>"
   if has_credentials then
      out[#out + 1] = "<p>Сохранённая сеть: <strong>" .. esc(st.wifi_sta_ssid) .. "</strong> (пароль сохранён на устройстве)</p>"
   else
      out[#out + 1] = '<p class="muted">Сохранённой сети нет.</p>'
   end
   if st.wifi_last_error then
      out[#out + 1] = '<p class="banner error">Последняя ошибка Wi-Fi: ' .. esc(st.wifi_last_error) .. "</p>"
   end
   out[#out + 1] = "</section>"
   return table.concat(out)
end

local function scan_html()
   local out = {
      '<section id="wifi-scan" class="card">',
      "<h2>Доступные сети</h2>",
   }
   if "ap" == st.wifi_mode then
      out[#out + 1] = '<p class="muted">Сканирование недоступно в режиме AP. Введите SSID вручную ниже.</p>'
   else
      out[#out + 1] = '<form method="post" action="/admin/wifi.lsp?fragment=scan"'
      out[#out + 1] = ' hx-post="/admin/wifi.lsp?fragment=scan" hx-target="#wifi-scan" hx-swap="outerHTML">'
      out[#out + 1] = '<input type="hidden" name="csrf" value="' .. esc(app.csrf_token()) .. '">'
      out[#out + 1] = '<div class="row">'
      out[#out + 1] = '<button type="submit" name="action" value="scan">Сканировать сети</button>'
      out[#out + 1] = '<span id="wifi-scan-indicator" class="muted htmx-indicator">Сканирование…</span>'
      out[#out + 1] = '<span class="muted">Если список пуст, введите SSID вручную ниже.</span>'
      out[#out + 1] = "</div></form>"
   end
   if scan and #scan > 0 then
      out[#out + 1] = '<div class="table-wrap"><table>'
      out[#out + 1] = "<thead><tr><th>SSID</th><th>RSSI</th><th>Канал</th><th>Защита</th><th></th></tr></thead><tbody>"
      for _, net in ipairs(scan) do
         out[#out + 1] = "<tr><td>" .. esc(net.ssid) .. "</td><td>" .. esc(net.rssi) .. " dBm</td><td>"
            .. esc(net.channel) .. "</td><td>" .. esc(net.authmode) .. '</td><td><a href="?pick='
            .. esc(ba.urlencode(net.ssid)) .. '">Выбрать</a></td></tr>'
      end
      out[#out + 1] = "</tbody></table></div>"
   end
   out[#out + 1] = "</section>"
   return table.concat(out)
end

if is_htmx then
   response:setheader("Content-Type", "text/html; charset=utf-8")
   response:setheader("Cache-Control", "no-store")
   if "status" == fragment then
      response:write(status_html(false))
   elseif "scan" == fragment then
      response:write(scan_html())
      if message then
         response:write(feedback_html(message, message_kind, true))
      end
   else
      response:write(feedback_html(message, message_kind, false))
      response:write(status_html(true))
   end
   return
end
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Wi-Fi — тёплый пол</title>
<script src="/static/theme.js"></script>
<script src="/static/htmx.min.js" defer></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=14">
</head>
<body>
<main>
<?lsp=app.ui_header{title="Wi-Fi", subtitle="Режим AP/STA и сохранённая сеть", active="settings"}?>
<?lsp=app.ui_settings_tabs("wifi")?>

<?lsp=feedback_html(message, message_kind, false)?>
<?lsp=status_html(false)?>
<?lsp=scan_html()?>

<section class="card">
  <h2>Подключение</h2>
  <form method="post" action="/admin/wifi.lsp?fragment=feedback" hx-post="/admin/wifi.lsp?fragment=feedback" hx-target="#wifi-feedback" hx-swap="outerHTML">
    <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
    <div class="form-grid">
      <label>SSID
        <input name="ssid" value="<?lsp=esc(pick)?>" autocomplete="off" spellcheck="false">
      </label>
      <label>Пароль
        <input name="pwd" type="password" autocomplete="new-password" placeholder="Пароль Wi-Fi">
      </label>
    </div>
    <?lsp if st.ap_jumper_closed then ?>
      <p class="banner">Джампер AP замкнут. Устройство останется в AP; для STA снимите джампер и перезагрузите устройство.</p>
    <?lsp end ?>
    <div class="row">
      <button type="submit" name="action" value="connect">Подключиться</button>
      <?lsp if has_credentials then ?>
        <button type="submit" name="action" value="sta" class="secondary">Использовать сохранённую</button>
      <?lsp end ?>
      <button type="submit" name="action" value="ap" class="secondary">Переключиться в AP</button>
    </div>
    <p class="muted">Переключение разрывает текущее соединение. В AP используйте сеть xedge32 и адрес http://192.168.190.0/.</p>
  </form>
</section>

<?lsp if has_credentials then ?>
<section class="card">
  <h2>Удаление</h2>
  <form method="post" action="/admin/wifi.lsp?fragment=feedback" hx-post="/admin/wifi.lsp?fragment=feedback" hx-target="#wifi-feedback" hx-swap="outerHTML" hx-confirm="Удалить сохранённую сеть и перейти в AP?">
    <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
    <button type="submit" name="action" value="forget" class="secondary">Забыть сеть и перейти в AP</button>
  </form>
</section>
<?lsp end ?>
</main>
</body>
</html>
