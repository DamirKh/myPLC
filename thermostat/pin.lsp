<?lsp
if not app.pin_configured() then
   response:sendredirect"/setup.lsp"
   return
end

local function safe_next(value)
   value = tostring(value or "")
   if value == "/" or value:match("^/admin/[%w%./_-]+$") then
      return value
   end
   return "/admin/settings.lsp"
end

local next_url = safe_next(request:data("next"))
if app.pin_valid(request) then
   response:sendredirect(next_url)
   return
end

local peer = request:peername() or ""
local locked, wait_seconds = app.pin_locked(peer)
local message = nil
local message_kind = "error"

if "POST" == request:method() then
   next_url = safe_next(request:data("next"))
   local origin = request:header("Origin")
   local host = request:header("Host")
   if origin and host and not origin:find(host, 1, true) then
      message = "Запрос отклонён: неверный Origin."
   elseif not app.csrf_valid(request:data("csrf")) then
      message = "Запрос отклонён: неверный CSRF-токен."
   elseif locked then
      message = "Слишком много попыток. Повторите позже."
   else
      local pin = request:data("pin")
      if app.pin_check(pin) then
         app.pin_success(peer)
         local token = app.pin_token(request)
         if not token then
            message = "Не удалось создать сессию."
         else
            local cookie = response:createcookie("thermo_pin")
            cookie:value(token)
            cookie:path"/"
            cookie:maxage(app.pin_session_seconds())
            cookie:httponly(true)
            cookie:secure(false)
            cookie:activate()
            response:sendredirect(next_url)
            return
         end
      else
         app.pin_fail(peer)
         locked, wait_seconds = app.pin_locked(peer)
         message = "Неверный PIN."
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
<div class="card" style="max-width:420px;margin:60px auto">
<h1>Вход в настройки</h1>
<p class="muted">Введите 4-значный PIN.</p>

<?lsp if message then ?><section class="banner <?lsp=message_kind?>"><?lsp=message?></section><?lsp end ?>
<?lsp if locked then ?>
<section class="banner error">Повторите попытку через <?lsp=wait_seconds or 0?> с.</section>
<?lsp end ?>

<form method="post">
  <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
  <input type="hidden" name="next" value="<?lsp=next_url?>">
  <label>PIN
    <input name="pin" type="password" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" required autocomplete="current-password" autofocus>
  </label>
  <div class="row" style="margin-top:16px">
    <button type="submit" <?lsp if locked then ?>disabled<?lsp end ?>>Войти</button>
    <a href="/" class="muted">Назад к обзору</a>
  </div>
</form>
</div>
</main>
</body>
</html>
