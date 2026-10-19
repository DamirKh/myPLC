<?lsp
if not app.pin_valid(request) then
   response:sendredirect"/pin.lsp?next=/admin/pin.lsp"
   return
end

local message = nil
local message_kind = "ok"
if "POST" == request:method() then
   if not app.csrf_valid(request:data("csrf")) then
      message = "Запрос отклонён: неверный CSRF-токен."
      message_kind = "error"
   else
      local current = request:data("current")
      local pin = request:data("pin")
      local confirm = request:data("confirm")
      if not app.pin_check(current) then
         message = "Неверный текущий PIN."
         message_kind = "error"
      elseif pin ~= confirm then
         message = "PIN-коды не совпадают."
         message_kind = "error"
      elseif not pin or not pin:match("^%d%d%d%d$") then
         message = "PIN должен состоять ровно из 4 цифр."
         message_kind = "error"
      else
         local ok, err = app.pin_set(pin)
         if ok then
            local cookie = response:createcookie("thermo_pin")
            cookie:path"/"
            cookie:maxage(0)
            cookie:httponly(true)
            cookie:activate()
            response:sendredirect"/pin.lsp?next=/admin/settings.lsp"
            return
         end
         message = tostring(err)
         message_kind = "error"
      end
   end
end
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PIN — тёплый пол</title>
<link rel="stylesheet" href="/static/style.css">
</head>
<body>
<main>
<header>
  <div><h1>Смена PIN</h1><p class="muted">Доступ по PIN</p></div>
  <nav><a href="/">Обзор</a><a href="/admin/settings.lsp">Настройки</a><a href="/admin/sensors.lsp">Датчики</a><a href="/admin/lock.lsp">Заблокировать</a></nav>
</header>

<?lsp if message then ?><section class="banner <?lsp=message_kind?>"><?lsp=message?></section><?lsp end ?>

<section class="card" style="max-width:520px">
<form method="post">
  <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
  <div class="form-grid">
    <label>Текущий PIN
      <input name="current" type="password" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" required autocomplete="current-password">
    </label>
    <label>Новый PIN
      <input name="pin" type="password" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" required autocomplete="new-password">
    </label>
    <label>Повторите новый PIN
      <input name="confirm" type="password" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" required autocomplete="new-password">
    </label>
  </div>
  <div class="row"><button type="submit">Сменить PIN</button></div>
</form>
</section>
</main>
</body>
</html>
