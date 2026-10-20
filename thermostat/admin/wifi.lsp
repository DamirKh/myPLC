<?lsp
if not app.pin_valid(request) then
   response:sendredirect"/pin.lsp?next=/admin/wifi.lsp"
   return
end

local message = nil
local message_kind = "ok"
local scan = nil
local csrf_ok = true
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
         message = "Подключение к «" .. tostring(result.ssid) .. "» запущено. Устройство переключится через 2 секунды."
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

local mode_text = st.wifi_mode or "—"
if "sta" == mode_text then
   mode_text = st.wifi_sta_connected and "STA, подключено" or "STA, нет подключения"
elseif "ap" == mode_text then
   mode_text = "AP"
end
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Wi-Fi — тёплый пол</title>
<script src="/static/theme.js"></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=8">
</head>
<body>
<main>
<header>
  <div><h1>Wi-Fi</h1><p class="muted">Режим AP/STA и сохранённая сеть</p></div>
  <nav><a href="/">Обзор</a><a href="/admin/settings.lsp">Настройки</a><a href="/admin/sensors.lsp">Датчики</a><a href="/admin/pin.lsp">PIN</a><a href="/admin/lock.lsp">Заблокировать</a></nav>
</header>

<?lsp if message then ?><section class="banner <?lsp=message_kind?>"><?lsp=esc(message)?></section><?lsp end ?>

<section class="card">
  <h2>Текущее состояние</h2>
  <p>Режим: <strong><?lsp=esc(mode_text)?></strong></p>
  <p>IP: <strong><?lsp=esc(st.wifi_ip or "—")?></strong></p>
  <?lsp if has_credentials then ?>
    <p>Сохранённая сеть: <strong><?lsp=esc(st.wifi_sta_ssid)?></strong> (пароль сохранён на устройстве)</p>
  <?lsp else ?>
    <p class="muted">Сохранённой сети нет.</p>
  <?lsp end ?>
  <?lsp if st.wifi_last_error then ?>
    <p class="banner error">Последняя ошибка Wi-Fi: <?lsp=esc(st.wifi_last_error)?></p>
  <?lsp end ?>
</section>

<section class="card">
  <h2>Доступные сети</h2>
  <form method="post">
    <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
    <div class="row">
      <button type="submit" name="action" value="scan">Сканировать сети</button>
      <span class="muted">Если список пуст, введите SSID вручную ниже.</span>
    </div>
  </form>

  <?lsp if scan then ?>
    <div class="table-wrap">
      <table>
        <thead><tr><th>SSID</th><th>RSSI</th><th>Канал</th><th>Защита</th><th></th></tr></thead>
        <tbody>
        <?lsp for _, net in ipairs(scan) do ?>
          <tr>
            <td><?lsp=esc(net.ssid)?></td>
            <td><?lsp=esc(net.rssi)?> dBm</td>
            <td><?lsp=esc(net.channel)?></td>
            <td><?lsp=esc(net.authmode)?></td>
            <td><a href="?pick=<?lsp=ba.urlencode(net.ssid)?>">Выбрать</a></td>
          </tr>
        <?lsp end ?>
        </tbody>
      </table>
    </div>
  <?lsp end ?>
</section>

<section class="card">
  <h2>Подключение</h2>
  <form method="post">
    <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
    <div class="form-grid">
      <label>SSID
        <input name="ssid" value="<?lsp=esc(pick)?>" autocomplete="off" spellcheck="false">
      </label>
      <label>Пароль
        <input name="pwd" type="password" autocomplete="new-password" placeholder="Пароль Wi-Fi">
      </label>
    </div>
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
  <form method="post" onsubmit="return confirm('Удалить сохранённую сеть и перейти в AP?')">
    <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
    <button type="submit" name="action" value="forget" class="secondary">Забыть сеть и перейти в AP</button>
  </form>
</section>
<?lsp end ?>
</main>
</body>
</html>
