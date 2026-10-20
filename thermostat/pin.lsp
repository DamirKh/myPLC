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
<script src="/static/theme.js"></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=8">
</head>
<body>
<main>
<div class="card pin-page" data-locked="<?lsp=locked and '1' or '0'?>">
<h1>Вход в настройки</h1>
<p class="muted">Введите 4-значный PIN.</p>

<?lsp if message then ?><section class="banner <?lsp=message_kind?>"><?lsp=message?></section><?lsp end ?>
<?lsp if locked then ?>
<section class="banner error">Повторите попытку через <?lsp=wait_seconds or 0?> с.</section>
<?lsp end ?>

<form method="post" id="pinForm" autocomplete="off">
  <input type="hidden" name="csrf" value="<?lsp=app.csrf_token()?>">
  <input type="hidden" name="next" value="<?lsp=next_url?>">
  <input type="hidden" name="pin" id="pinInput" value="">

  <div id="pinDisplay" class="pin-display" role="status" aria-live="polite" aria-label="Введено 0 из 4 цифр">
    <span class="pin-dot"></span>
    <span class="pin-dot"></span>
    <span class="pin-dot"></span>
    <span class="pin-dot"></span>
  </div>

  <div class="pin-pad" role="group" aria-label="Цифровая клавиатура">
    <button type="button" class="pin-key" data-digit="1" aria-label="Цифра 1">1</button>
    <button type="button" class="pin-key" data-digit="2" aria-label="Цифра 2">2</button>
    <button type="button" class="pin-key" data-digit="3" aria-label="Цифра 3">3</button>
    <button type="button" class="pin-key" data-digit="4" aria-label="Цифра 4">4</button>
    <button type="button" class="pin-key" data-digit="5" aria-label="Цифра 5">5</button>
    <button type="button" class="pin-key" data-digit="6" aria-label="Цифра 6">6</button>
    <button type="button" class="pin-key" data-digit="7" aria-label="Цифра 7">7</button>
    <button type="button" class="pin-key" data-digit="8" aria-label="Цифра 8">8</button>
    <button type="button" class="pin-key" data-digit="9" aria-label="Цифра 9">9</button>
    <button type="button" class="pin-key action" data-action="clear" aria-label="Очистить PIN" title="Очистить">C</button>
    <button type="button" class="pin-key" data-digit="0" aria-label="Цифра 0">0</button>
    <button type="button" class="pin-key action" data-action="back" aria-label="Стереть последнюю цифру" title="Стереть">⌫</button>
  </div>

  <button id="pinSubmit" class="pin-submit" type="submit" <?lsp if locked then ?>disabled<?lsp end ?>>Войти</button>
</form>

<p class="muted pin-hint">Можно также использовать клавиатуру: 0–9, Backspace, Enter.</p>
<p><a href="/">Назад к обзору</a></p>
</div>
</main>

<script>
(function () {
   const form = document.getElementById('pinForm');
   const input = document.getElementById('pinInput');
   const display = document.getElementById('pinDisplay');
   const submit = document.getElementById('pinSubmit');
   const dots = Array.from(display.querySelectorAll('.pin-dot'));
   const keys = Array.from(document.querySelectorAll('.pin-key'));
   const locked = document.querySelector('.pin-page').dataset.locked === '1';
   let pin = '';

   function render() {
      input.value = pin;
      dots.forEach((dot, index) => dot.classList.toggle('filled', index < pin.length));
      display.setAttribute('aria-label', 'Введено ' + pin.length + ' из 4 цифр');
      submit.disabled = locked || pin.length !== 4;
   }

   function addDigit(digit) {
      if (locked || pin.length >= 4) return;
      pin += digit;
      render();
   }

   function backspace() {
      if (locked || pin.length === 0) return;
      pin = pin.slice(0, -1);
      render();
   }

   function clearPin() {
      if (locked) return;
      pin = '';
      render();
   }

   keys.forEach(button => {
      button.addEventListener('click', () => {
         if (button.dataset.digit) addDigit(button.dataset.digit);
         else if (button.dataset.action === 'back') backspace();
         else if (button.dataset.action === 'clear') clearPin();
      });
   });

   document.addEventListener('keydown', event => {
      if (locked) return;
      if (event.key >= '0' && event.key <= '9') {
         addDigit(event.key);
         event.preventDefault();
      } else if (event.key === 'Backspace') {
         backspace();
         event.preventDefault();
      } else if (event.key === 'Escape') {
         clearPin();
      } else if (event.key === 'Enter' && pin.length === 4 && 'BUTTON' !== event.target.tagName) {
         form.requestSubmit();
         event.preventDefault();
      }
   });

   form.addEventListener('submit', event => {
      if (locked || pin.length !== 4) {
         event.preventDefault();
         return;
      }
      keys.forEach(button => button.disabled = true);
      submit.disabled = true;
      submit.textContent = 'Проверка…';
   });

   if (locked) {
      keys.forEach(button => button.disabled = true);
   }
   render();
})();
</script>
</body>
</html>
