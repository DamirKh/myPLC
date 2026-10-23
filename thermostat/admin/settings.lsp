<?lsp
if not app.pin_valid(request) then
   response:sendredirect"/pin.lsp?next=/admin/settings.lsp"
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
   local origin = request:header("Origin")
   local host = request:header("Host")
   if origin and host and not origin:find(host, 1, true) then
      csrf_ok = false
      message = "Запрос отклонён: неверный Origin"
      message_kind = "error"
   end
end

local utc_offset = app.offset_from_parts(
   request:data("utc_offset_hours"),
   request:data("utc_offset_minutes")
)
if "POST" == request:method() and csrf_ok and not utc_offset then
   csrf_ok = false
   message = "Некорректное смещение UTC. Часы: от −12 до +14, минуты: 0 или 30 (для −00:30 укажите −30)."
   message_kind = "error"
end

if "POST" == request:method() and csrf_ok then
   local mqtt_host = tostring(request:data("mqtt_host") or ""):match("^%s*(.-)%s*$")
   local patch = {
      control = {
         target_room = tonumber(request:data("target_room")),
         floor_limit = tonumber(request:data("floor_limit")),
         room_hysteresis = tonumber(request:data("room_hysteresis")),
         floor_hysteresis = tonumber(request:data("floor_hysteresis")),
         min_on_sec = tonumber(request:data("min_on_sec")),
         min_off_sec = tonumber(request:data("min_off_sec")),
         frost_enabled = request:data("frost_enabled") and true or false,
         frost_threshold = tonumber(request:data("frost_threshold")),
      },
      schedule = {
         enabled = request:data("schedule_enabled") and true or false,
         utc_offset_minutes = utc_offset,
      },
      mqtt = {
         enabled = request:data("mqtt_enabled") and true or false,
         host = mqtt_host,
         port = tonumber(request:data("mqtt_port")),
         tls = request:data("mqtt_tls") and true or false,
         username = request:data("mqtt_username") or "",
         base_topic = request:data("mqtt_base_topic") or "",
         ha_discovery = request:data("mqtt_ha") and true or false,
      },
      ui = {
         public_setpoint = request:data("public_setpoint") and true or false,
         public_setpoint_min = tonumber(request:data("public_setpoint_min")),
         public_setpoint_max = tonumber(request:data("public_setpoint_max")),
      },
   }
   local pwd = request:data("mqtt_password")
   if pwd and "" ~= pwd and "***" ~= pwd then
      patch.mqtt.password = pwd
   end
   local ok, result = app.update_config(patch)
   if ok then
      message = "Настройки сохранены"
      message_kind = "ok"
   else
      if "table" == type(result) then
         result = table.concat(result, "; ")
      end
      message = "Ошибка: " .. tostring(result)
      message_kind = "error"
   end
end

local cfg = app.get_config()
local c = cfg.control
local s = cfg.schedule
local m = cfg.mqtt
local ui = cfg.ui
local function checked(v) return v and "checked" or "" end

local current_offset = app.rounded_utc_offset(s.utc_offset_minutes or 0)
local offset_abs = math.abs(current_offset)
local offset_hours = math.floor(offset_abs / 60)
if current_offset < 0 then
   offset_hours = -offset_hours
end
local offset_minutes = offset_abs % 60
if current_offset < 0 and 0 == offset_hours then
   offset_minutes = -offset_minutes
end
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Настройки — тёплый пол</title>
<script src="/static/theme.js"></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=8">
</head>
<body>
<main>
<header>
  <div><h1>Настройки</h1><p class="muted">Доступ по PIN</p></div>
  <nav><a href="/">Обзор</a><a href="/admin/sensors.lsp">Датчики</a><a href="/admin/wifi.lsp">Wi-Fi</a><a href="/history.lsp">История</a><a href="/admin/pin.lsp">PIN</a><a href="/admin/lock.lsp">Заблокировать</a></nav>
</header>

<?lsp if message then ?><section class="banner <?lsp=message_kind?>"><?lsp=message?></section><?lsp end ?>

<form method="post" class="card">
  <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
  <h2>Управление</h2>
  <div class="form-grid">
    <label>Базовая температура в комнате, °C
      <input name="target_room" type="number" min="5" max="35" step="0.5" value="<?lsp=c.target_room?>" required>
    </label>
    <label>Нижняя граница уставки воздуха, °C
      <input name="public_setpoint_min" type="number" min="5" max="35" step="0.5" value="<?lsp=ui.public_setpoint_min?>" required>
    </label>
    <label>Верхняя граница уставки воздуха, °C
      <input name="public_setpoint_max" type="number" min="5" max="35" step="0.5" value="<?lsp=ui.public_setpoint_max?>" required>
    </label>
    <label>Предел температуры пола, °C
      <input name="floor_limit" type="number" min="10" max="45" step="0.5" value="<?lsp=c.floor_limit?>" required>
    </label>
    <label>Гистерезис комнаты, °C
      <input name="room_hysteresis" type="number" min="0" max="5" step="0.1" value="<?lsp=c.room_hysteresis?>">
    </label>
    <label>Гистерезис пола, °C
      <input name="floor_hysteresis" type="number" min="0" max="5" step="0.1" value="<?lsp=c.floor_hysteresis?>">
    </label>
    <label>Минимальное время работы, с
      <input name="min_on_sec" type="number" min="0" max="3600" step="10" value="<?lsp=c.min_on_sec?>">
    </label>
    <label>Минимальная пауза, с
      <input name="min_off_sec" type="number" min="0" max="3600" step="10" value="<?lsp=c.min_off_sec?>">
    </label>
    <label class="check"><input name="frost_enabled" type="checkbox" <?lsp=checked(c.frost_enabled)?>> Защита от замерзания</label>
    <label>Порог замерзания, °C
      <input name="frost_threshold" type="number" min="-20" max="20" step="0.5" value="<?lsp=c.frost_threshold?>">
    </label>
    <label class="check"><input name="public_setpoint" type="checkbox" <?lsp=checked(ui.public_setpoint)?>> Разрешить менять уставку без входа</label>
  </div>
  <p class="muted">Границы ограничивают изменение уставки воздуха; базовая уставка должна входить в этот диапазон.</p>

  <h2>Время и расписание</h2>
  <div class="form-grid">
    <label class="check"><input name="schedule_enabled" type="checkbox" <?lsp=checked(s.enabled)?>> Расписание включено</label>
    <label>Смещение UTC: часы
      <input name="utc_offset_hours" type="number" min="-12" max="14" step="1" value="<?lsp=offset_hours?>" required>
    </label>
    <label>Смещение UTC: минуты
      <input name="utc_offset_minutes" type="number" min="-30" max="30" step="30" value="<?lsp=offset_minutes?>" required>
    </label>
  </div>
  <p class="muted">Шаг смещения — 30 минут. Знак задаётся часами; для смещения меньше часа используйте минуты со знаком, например 0 ч и −30 мин.</p>
  <p class="muted">Расписание редактируется на отдельной странице (следующий этап).</p>

  <h2>MQTT</h2>
  <div class="form-grid">
    <label class="check"><input name="mqtt_enabled" type="checkbox" <?lsp=checked(m.enabled)?>> MQTT включён</label>
    <label>Сервер
      <input name="mqtt_host" value="<?lsp=m.host?>">
    </label>
    <label>Порт
      <input name="mqtt_port" type="number" min="1" max="65535" value="<?lsp=m.port?>">
    </label>
    <label class="check"><input name="mqtt_tls" type="checkbox" <?lsp=checked(m.tls)?>> TLS</label>
    <label>Пользователь
      <input name="mqtt_username" value="<?lsp=m.username?>">
    </label>
    <label>Пароль
      <input name="mqtt_password" type="password" value="<?lsp=m.password?>" placeholder="оставьте *** чтобы не менять">
    </label>
    <label>Base topic
      <input name="mqtt_base_topic" value="<?lsp=m.base_topic?>">
    </label>
    <label class="check"><input name="mqtt_ha" type="checkbox" <?lsp=checked(m.ha_discovery)?>> Home Assistant discovery</label>
  </div>

  <div class="row"><button type="submit">Сохранить</button></div>
</form>

<div class="card">
  <h2>Текущие датчики</h2>
  <table>
    <thead><tr><th>Роль</th><th>Метка</th><th>Шина</th><th>ROM</th></tr></thead>
    <tbody>
    <?lsp for _,x in ipairs(cfg.sensor_list or {}) do ?>
      <tr><td><?lsp=x.role?></td><td><?lsp=x.label or ""?></td><td><?lsp=x.bus?></td><td><code><?lsp=x.rom?></code></td></tr>
    <?lsp end ?>
    </tbody>
  </table>
  <p><a href="/admin/sensors.lsp">Поиск и назначение ролей</a></p>
</div>
</main>
</body>
</html>
