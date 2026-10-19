<?lsp
if app.pin_configured() then
   response:sendredirect"/admin/settings.lsp"
   return
end

local peer = request:peername()
local server = request:sockname()
local available = app.pin_available()
local trusted = app.pin_trusted(peer, server)

local message = nil
local message_kind = "error"
if "POST" == request:method() then
   if not app.csrf_valid(request:data("csrf")) then
      message = "Запрос отклонён: неверный CSRF-токен."
   else
      local pin = request:data("pin")
      local confirm = request:data("confirm")
      if pin ~= confirm then
         message = "PIN-коды не совпадают."
      elseif not pin or not pin:match("^%d%d%d%d$") then
         message = "PIN должен состоять ровно из 4 цифр."
      else
         local ok, err = app.pin_set(pin)
         if ok then
            response:sendredirect"/pin.lsp?next=/admin/settings.lsp"
            return
         end
         message = tostring(err)
      end
   end
end
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Первичная настройка — тёплый пол</title>
<link rel="stylesheet" href="/static/style.css">
</head>
<body>
<main>
<div class="card" style="max-width:520px;margin:60px auto">
<h1>Первичная настройка</h1>

<?lsp if not available then ?>
<section class="banner error">
Генератор ключей недоступен: настройка PIN отключена. Проверьте прошивку Xedge32.
</section>
<p><a href="/">Назад к обзору</a></p>
<?lsp elseif not trusted then ?>
<section class="banner error">
Создание PIN разрешено только с доверенной локальной сети. Подключитесь к AP
`xedge32` или к той же подсети, что и контроллер, и обновите страницу.
</section>
<p><a href="/">Назад к обзору</a></p>
<?lsp else ?>
<p class="muted">
PIN нужен только для входа в настройки. Обзор и изменение уставки остаются
доступными без PIN. Эта страница доступна только пока PIN не задан.
</p>

<?lsp if message then ?><section class="banner <?lsp=message_kind?>"><?lsp=message?></section><?lsp end ?>

<form method="post">
  <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
  <div class="form-grid">
    <label>PIN (4 цифры)
      <input name="pin" type="password" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" required autocomplete="new-password" autofocus>
    </label>
    <label>Повторите PIN
      <input name="confirm" type="password" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" required autocomplete="new-password">
    </label>
  </div>
  <div class="row"><button type="submit">Сохранить PIN</button></div>
</form>
<?lsp end ?>
</div>
</main>
</body>
</html>
