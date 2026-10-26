<?lsp
if not app.pin_guard(request, response, "/admin/pin.lsp") then
   return
end

local message = nil
local message_kind = "ok"
local is_htmx = app.htmx_request(request)

local function feedback_html(text, kind)
   local body = ""
   if text then
      body = '<section class="banner ' .. tostring(kind or "ok") .. '">' .. tostring(text) .. "</section>"
   end
   return '<div id="pin-feedback">' .. body .. "</div>"
end

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
            if is_htmx then
               app.htmx_redirect(response, "/pin.lsp?next=/admin/settings.lsp")
            else
               response:sendredirect"/pin.lsp?next=/admin/settings.lsp"
            end
            return
         end
         message = tostring(err)
         message_kind = "error"
      end
   end
end

if is_htmx then
   response:setheader("Content-Type", "text/html; charset=utf-8")
   response:setheader("Cache-Control", "no-store")
   response:write(feedback_html(message, message_kind))
   return
end
?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PIN — тёплый пол</title>
<script src="/static/theme.js"></script>
<script src="/static/htmx.min.js" defer></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=14">
</head>
<body>
<main>
<?lsp=app.ui_header{title="PIN", subtitle="Доступ к настройкам", active="settings"}?>
<?lsp=app.ui_settings_tabs("pin")?>

<?lsp=feedback_html(message, message_kind)?>

<section class="card" style="max-width:520px">
<form method="post" action="/admin/pin.lsp" hx-post="/admin/pin.lsp" hx-target="#pin-feedback" hx-swap="outerHTML">
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
