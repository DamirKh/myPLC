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
   elseif "reset_hours" == action then
      local ok = app.reset_pump_hours()
      response:sendredirect("/admin/sensors.lsp?" .. (ok and "hours=1" or "err=hours"))
      return
   elseif "apply" == action then
      local decoded, rows = pcall(ba.json.decode, request:data("payload") or "")
      if not decoded or "table" ~= type(rows) then
         response:sendredirect("/admin/sensors.lsp?err=apply")
         return
      end
      local ok = app.update_sensors(rows)
      response:sendredirect("/admin/sensors.lsp?" .. (ok and "saved=1" or "err=apply"))
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
  <div class="row" style="margin-top:16px">
    <form method="post" class="inline">
      <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
      <input type="hidden" name="action" value="scan">
      <button type="submit" class="secondary">Пересканировать шины</button>
    </form>
    <form method="post" class="inline" onsubmit="return confirm('Сбросить моточасы насоса?')">
      <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
      <input type="hidden" name="action" value="reset_hours">
      <button type="submit" class="secondary">Сбросить моточасы</button>
    </form>
    <span class="muted">Моточасы: <?lsp=("number" == type(pump_hours)) and string.format("%.1f ч", pump_hours) or "—"?></span>
    <?lsp if sensor_table.scan_active then ?><span class="muted">Идёт сканирование…</span><?lsp end ?>
  </div>
  <?lsp end ?>
</section>

<section class="card">
  <h2>Датчики</h2>
  <?lsp if not service then ?>
  <p class="banner">Включите сервисный режим, чтобы менять роли, метки и смещения.</p>
  <?lsp end ?>
  <form id="sensor-form" method="post">
    <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
    <input type="hidden" name="action" value="apply">
    <input type="hidden" name="payload" id="sensor-payload" value="">
    <div class="table-wrap">
    <table class="sensor-table">
      <thead>
        <tr><th>ROM</th><th>Температура</th><th>Статус</th><th>Роль</th><th>Метка</th><th>Смещение</th></tr>
      </thead>
      <?lsp for _, bus in ipairs(sensor_table.buses or {}) do ?>
      <tbody>
        <tr class="bus-row"><th colspan="6">Шина <code><?lsp=bus.name?></code> · GPIO <?lsp=bus.pin?> · датчиков: <?lsp=#(bus.sensors or {})?></th></tr>
        <?lsp if 0 == #(bus.sensors or {}) then ?>
        <tr><td colspan="6" class="muted">Датчики не найдены</td></tr>
        <?lsp end ?>
        <?lsp for _, sensor in ipairs(bus.sensors or {}) do ?>
        <tr data-key="<?lsp=sensor.key?>" data-bus="<?lsp=bus.name?>" data-rom="<?lsp=sensor.rom?>">
          <td><code class="sensor-rom"><?lsp=sensor.rom?></code></td>
          <td class="sensor-temp"><span data-temp><?lsp=fmt_temp(sensor.temp)?></span><span class="rise-icon" data-rise title="<?lsp=sensor.rise_top and 'Максимальный рост температуры' or ''?>"><?lsp=sensor.rise_top and '↑' or ''?></span></td>
          <td><span class="sensor-status <?lsp=sensor.ok and 'ok' or 'error'?>" data-status><?lsp=status_text(sensor)?></span></td>
          <td>
            <select data-field="role" <?lsp if not service then ?>disabled<?lsp end ?>>
              <?lsp=role_options(sensor.role)?>
            </select>
          </td>
          <td><input data-field="label" class="sensor-label-input" value="<?lsp=esc(sensor.label)?>" <?lsp if not service then ?>disabled<?lsp end ?>></td>
          <td><input data-field="offset" class="sensor-offset-input" type="number" step="0.1" value="<?lsp=string.format("%.1f", sensor.offset or 0)?>" <?lsp if not service then ?>disabled<?lsp end ?>></td>
        </tr>
        <?lsp end ?>
      </tbody>
      <?lsp end ?>
    </table>
    </div>
    <?lsp if service then ?>
    <div class="row sensor-actions">
      <button type="submit">Применить</button>
      <button type="reset" class="secondary">Отмена</button>
    </div>
    <?lsp end ?>
  </form>
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
      var all = [];
      document.querySelectorAll("[data-key]").forEach(function (row) {
         rows[row.getAttribute("data-key")] = row;
      });
      (data.buses || []).forEach(function (bus) {
         var sensors = bus.sensors || [];
         if (!Array.isArray(sensors)) sensors = Object.values(sensors);
         sensors.forEach(function (item) {
            all.push(item);
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
      var maxDelta = null;
      all.forEach(function (item) {
         if (item.ok && typeof item.delta === "number" && item.delta > 0
            && (maxDelta === null || item.delta > maxDelta)) {
            maxDelta = item.delta;
         }
      });
      all.forEach(function (item) {
         var row = rows[item.key];
         if (!row) return;
         var rise = row.querySelector("[data-rise]");
         if (!rise) return;
         var top = maxDelta !== null && item.ok && item.delta === maxDelta;
         rise.textContent = top ? "↑" : "";
         rise.title = top ? "Максимальный рост температуры" : "";
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
   var form = document.getElementById("sensor-form");
   if (form) {
      form.addEventListener("submit", function (event) {
         event.preventDefault();
         var rows = [];
         document.querySelectorAll("tr[data-key]").forEach(function (row) {
            var role = row.querySelector('[data-field="role"]');
            var label = row.querySelector('[data-field="label"]');
            var offset = row.querySelector('[data-field="offset"]');
            rows.push({
               bus: row.getAttribute("data-bus"),
               rom: row.getAttribute("data-rom"),
               role: role ? role.value : "",
               label: label ? label.value : "",
               offset: offset ? offset.value : "0",
            });
         });
         document.getElementById("sensor-payload").value = JSON.stringify(rows);
         form.submit();
      });
   }
   refresh();
   setInterval(refresh, service ? 2000 : 10000);
})();
</script>
</body>
</html>
