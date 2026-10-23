<?lsp
if not app.pin_valid(request) then
   response:sendredirect"/pin.lsp?next=/admin/sensors.lsp"
   return
end

local message = nil
local message_kind = "ok"
local csrf_ok = true
if "POST" == request:method() then
   if not app.csrf_valid(request:data("csrf")) then
      csrf_ok = false
      message = "Запрос отклонён: неверный CSRF-токен"
      message_kind = "error"
   end
end

if "POST" == request:method() and csrf_ok then
   local action = request:data("action")
   if "service" == action then
      local on = "on" == request:data("state")
      app.set_service_mode(on)
      response:sendredirect("/admin/sensors.lsp?service=" .. (on and "on" or "off"))
      return
   elseif "scan" == action then
      local result = app.scan_sensors()
      local status = result and result.status or "queued"
      response:sendredirect("/admin/sensors.lsp?scan=" .. status)
      return
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
      response:sendredirect("/admin/sensors.lsp?" .. (ok and "saved=1" or "err=assign"))
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
   message = "Роль и параметры датчика сохранены."
elseif request:data("err") then
   message = "Не удалось сохранить датчик. Проверьте роль, ROM и конфигурацию."
   message_kind = "error"
end

local service = app.service_mode_enabled()
local sensor_table = app.get_sensor_table()
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
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<?lsp if service and sensor_table.scan_active then ?><meta http-equiv="refresh" content="2"><?lsp end ?>
<title>Датчики — тёплый пол</title>
<script src="/static/theme.js"></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=9">
</head>
<body>
<main>
<header>
  <div><h1>Датчики</h1><p class="muted">Одна таблица по шинам: поиск, температуры и роли</p></div>
  <nav><a href="/">Обзор</a><a href="/admin/settings.lsp">Настройки</a><a href="/admin/wifi.lsp">Wi-Fi</a><a href="/history.lsp">История</a><a href="/admin/pin.lsp">PIN</a><a href="/admin/lock.lsp">Заблокировать</a></nav>
</header>

<?lsp if message then ?><section class="banner <?lsp=message_kind?>"><?lsp=message?></section><?lsp end ?>

<section class="card">
  <div class="service-head">
    <div>
      <h2>Сервисный режим</h2>
      <p class="muted">Насос выключен, датчики читаются часто. Роли и параметры можно менять только здесь.</p>
    </div>
    <div class="service-actions">
      <span class="service-state <?lsp=service and 'on' or 'off'?>"><?lsp=service and 'включён' or 'выключен'?></span>
      <form method="post" class="inline">
        <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
        <input type="hidden" name="action" value="service">
        <input type="hidden" name="state" value="<?lsp=service and 'off' or 'on'?>">
        <button type="submit" class="<?lsp=service and 'secondary' or ''?>"><?lsp=service and 'Выключить сервисный режим' or 'Включить сервисный режим'?></button>
      </form>
    </div>
  </div>
  <?lsp if service then ?>
  <form method="post" class="row" style="margin-top:16px">
    <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
    <input type="hidden" name="action" value="scan">
    <button type="submit" class="secondary">Пересканировать шины</button>
    <?lsp if sensor_table.scan_active then ?><span class="muted">Идёт сканирование…</span><?lsp end ?>
  </form>
  <?lsp end ?>
</section>

<section class="card">
  <h2>Датчики</h2>
  <?lsp if not service then ?>
  <p class="banner">Включите сервисный режим, чтобы менять роли, метки и смещения.</p>
  <?lsp end ?>
  <div class="table-wrap">
  <table class="sensor-table">
    <thead>
      <tr><th>ROM</th><th>Температура</th><th>Статус</th><th>Роль</th><th>Метка</th><th>Смещение</th><th></th></tr>
    </thead>
    <?lsp for _, bus in ipairs(sensor_table.buses or {}) do ?>
    <tbody>
      <tr class="bus-row"><th colspan="7">Шина <code><?lsp=bus.name?></code> · GPIO <?lsp=bus.pin?> · датчиков: <?lsp=#(bus.sensors or {})?></th></tr>
      <?lsp if 0 == #(bus.sensors or {}) then ?>
      <tr><td colspan="7" class="muted">Датчики не найдены</td></tr>
      <?lsp end ?>
      <?lsp for index, sensor in ipairs(bus.sensors or {}) do ?>
      <?lsp local form_id = "assign-" .. bus.name .. "-" .. index ?>
      <tr data-key="<?lsp=sensor.key?>">
        <td><code class="sensor-rom"><?lsp=sensor.rom?></code></td>
        <td class="sensor-temp" data-temp><?lsp=fmt_temp(sensor.temp)?></td>
        <td><span class="sensor-status <?lsp=sensor.ok and 'ok' or 'error'?>" data-status><?lsp=status_text(sensor)?></span></td>
        <td>
          <form id="<?lsp=form_id?>" method="post" class="inline">
            <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
            <input type="hidden" name="action" value="assign">
            <input type="hidden" name="bus" value="<?lsp=bus.name?>">
            <input type="hidden" name="rom" value="<?lsp=sensor.rom?>">
          </form>
          <select name="role" form="<?lsp=form_id?>" <?lsp if not service then ?>disabled<?lsp end ?>>
            <?lsp=role_options(sensor.role)?>
          </select>
        </td>
        <td><input name="label" form="<?lsp=form_id?>" class="sensor-label-input" value="<?lsp=esc(sensor.label)?>" <?lsp if not service then ?>disabled<?lsp end ?>></td>
        <td><input name="offset" form="<?lsp=form_id?>" class="sensor-offset-input" type="number" step="0.1" value="<?lsp=string.format("%.1f", sensor.offset or 0)?>" <?lsp if not service then ?>disabled<?lsp end ?>></td>
        <td class="actions"><button type="submit" form="<?lsp=form_id?>" <?lsp if not service then ?>disabled<?lsp end ?>>Применить</button></td>
      </tr>
      <?lsp end ?>
    </tbody>
    <?lsp end ?>
  </table>
  </div>
</section>
</main>
<script>
(function () {
   var service = <?lsp=service and "true" or "false"?>;
   function fmtTemp(value) {
      return typeof value === "number" ? value.toFixed(2) + " °C" : "—";
   }
   function statusText(item) {
      if (item.ok) return "OK";
      var err = item.err;
      if (err === "not_found") return "не найден";
      if (err === "not_read") return "нет данных";
      if (err === "no presence") return "нет связи";
      if (err === "CRC error") return "ошибка CRC";
      if (err === "timeout") return "таймаут";
      if (err === "power_on_reset_85C") return "85 °C после включения";
      return err || "—";
   }
   function apply(data) {
      var rows = {};
      document.querySelectorAll("[data-key]").forEach(function (row) {
         rows[row.getAttribute("data-key")] = row;
      });
      (data.buses || []).forEach(function (bus) {
         var sensors = bus.sensors || [];
         if (!Array.isArray(sensors)) sensors = Object.values(sensors);
         sensors.forEach(function (item) {
            var row = rows[item.key];
            if (!row) return;
            var temp = row.querySelector("[data-temp]");
            var status = row.querySelector("[data-status]");
            if (temp) temp.textContent = fmtTemp(item.temp);
            if (status) {
               status.textContent = statusText(item);
               status.className = "sensor-status " + (item.ok ? "ok" : "error");
            }
         });
      });
   }
   async function refresh() {
      try {
         var response = await fetch("/admin/sensors_data.lsp", { cache: "no-store" });
         if (!response.ok) return;
         apply(await response.json());
      } catch (error) {
      }
   }
   setInterval(refresh, service ? 2000 : 10000);
})();
</script>
</body>
</html>
