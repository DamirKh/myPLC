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
   local ok, err
   if "scan" == action then
      local result = app.scan_sensors()
      ok = true
      message = (result and "running" == result.status)
         and "Сканирование уже выполняется"
         or "Сканирование запущено"
   elseif "assign" == action then
      ok, err = app.assign_sensor(
         request:data("bus"),
         request:data("rom"),
         request:data("role"),
         request:data("label"),
         tonumber(request:data("offset"))
      )
      message = ok and "Роль назначена" or ("Ошибка: " .. tostring(err))
      message_kind = ok and "ok" or "error"
   elseif "remove" == action then
      ok, err = app.remove_sensor(request:data("bus"), request:data("rom"))
      message = ok and "Датчик удалён" or ("Ошибка: " .. tostring(err))
      message_kind = ok and "ok" or "error"
   end
end

local cfg = app.get_config()
local scan = app.get_scan_result()
local scan_status = app.scan_status() or {}
local scan_active = scan_status.running or scan_status.requested
local found = 0
if scan then
   for _, bus in ipairs(scan.buses or {}) do
      found = found + #(bus.roms or {})
   end
end
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<?lsp if scan_active then ?><meta http-equiv="refresh" content="2"><?lsp end ?>
<title>Датчики — тёплый пол</title>
<script src="/static/theme.js"></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=8">
</head>
<body>
<main>
<header>
  <div><h1>Датчики</h1><p class="muted">Поиск ROM и назначение ролей</p></div>
  <nav><a href="/">Обзор</a><a href="/admin/settings.lsp">Настройки</a><a href="/history.lsp">История</a><a href="/admin/pin.lsp">PIN</a><a href="/admin/lock.lsp">Заблокировать</a></nav>
</header>

<?lsp if message then ?><section class="banner <?lsp=message_kind?>"><?lsp=message?></section><?lsp end ?>
<?lsp if scan_active then ?>
<section class="banner">Идёт сканирование шин. Страница обновится автоматически.</section>
<?lsp end ?>

<section class="card">
  <h2>Сканирование шин</h2>
  <p class="muted">Скан выполняется в сервисном режиме: насос выключается, контроллер приостанавливается.</p>
  <form method="post">
    <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
    <input type="hidden" name="action" value="scan">
    <button type="submit">Сканировать все шины</button>
  </form>
</section>

<?lsp if scan then ?>
<section class="card">
  <h2>Результат сканирования</h2>
  <?lsp if 0 == found then ?>
    <p class="banner">Датчики не найдены. Проверьте питание 3.3 В, линию DQ и подтяжку 4.7 кОм на каждой шине.</p>
  <?lsp end ?>
  <?lsp for _, bus in ipairs(scan.buses or {}) do ?>
    <h3>Шина <?lsp=bus.name?></h3>
    <table>
      <thead><tr><th>ROM</th><th>Температура</th><th>Ошибка</th></tr></thead>
      <tbody>
      <?lsp for _, x in ipairs(bus.roms or {}) do ?>
        <tr><td><code><?lsp=x.rom?></code></td><td><?lsp=x.temp and string.format("%.2f °C", x.temp) or "—"?></td><td><?lsp=x.err or ""?></td></tr>
      <?lsp end ?>
      </tbody>
    </table>
  <?lsp end ?>
  <?lsp if scan.errors and #scan.errors > 0 then ?>
    <p class="banner error">Не удалось опросить одну или несколько шин. Проверьте подключение датчиков и подтяжку 4.7 кОм.</p>
    <pre class="muted"><?lsp=table.concat(scan.errors, "\n")?></pre>
  <?lsp end ?>
</section>
<?lsp end ?>

<section class="card">
  <h2>Назначить роль</h2>
  <form method="post" class="form-grid">
    <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
    <input type="hidden" name="action" value="assign">
    <label>Шина
      <select name="bus">
        <option value="control_a">control_a (воздух + пол)</option>
        <option value="control_b">control_b (воздух + пол)</option>
        <option value="diag">diag (диагностика)</option>
      </select>
    </label>
    <label>ROM
      <input name="rom" placeholder="28AABBCCDDEEFFCRC" required>
    </label>
    <label>Роль
      <select name="role">
        <option value="room">room — воздух</option>
        <option value="floor">floor — пол</option>
        <option value="supply">supply — подача</option>
        <option value="return">return — обратка</option>
        <option value="pump">pump — насос</option>
        <option value="extra">extra — прочее</option>
      </select>
    </label>
    <label>Метка
      <input name="label" placeholder="например, комната">
    </label>
    <label>Смещение, °C
      <input name="offset" type="number" step="0.1" value="0">
    </label>
    <div class="row"><button type="submit">Назначить</button></div>
  </form>
</section>

<section class="card">
  <h2>Назначенные датчики</h2>
  <table>
    <thead><tr><th>Роль</th><th>Метка</th><th>Шина</th><th>ROM</th><th>Смещение</th><th></th></tr></thead>
    <tbody>
    <?lsp for _, x in ipairs(cfg.sensor_list or {}) do ?>
      <tr>
        <td><?lsp=x.role?></td>
        <td><?lsp=x.label or ""?></td>
        <td><?lsp=x.bus?></td>
        <td><code><?lsp=x.rom?></code></td>
        <td><?lsp=string.format("%.1f", x.offset or 0)?></td>
        <td>
          <form method="post" class="inline">
            <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
            <input type="hidden" name="action" value="remove">
            <input type="hidden" name="bus" value="<?lsp=x.bus?>">
            <input type="hidden" name="rom" value="<?lsp=x.rom?>">
            <button class="secondary" type="submit">Удалить</button>
          </form>
        </td>
      </tr>
    <?lsp end ?>
    </tbody>
  </table>
</section>
</main>
</body>
</html>
