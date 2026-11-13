<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>
(function () {
   try {
      var saved = localStorage.getItem('thermostat.view');
      var auto = window.matchMedia('(max-width: 640px)').matches ? 'compact' : 'full';
      document.documentElement.dataset.view = (saved === 'compact' || saved === 'full') ? saved : auto;
   } catch (e) {
      document.documentElement.dataset.view = window.matchMedia('(max-width: 640px)').matches ? 'compact' : 'full';
   }
})();
</script>
<script src="/static/theme.js"></script>
<title>Тёплый пол</title>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="static/style.css?v=14">
</head>
<body>
<svg xmlns="http://www.w3.org/2000/svg" class="icon-sprite" aria-hidden="true">
   <symbol id="i-house" viewBox="0 0 24 24"><path d="M3 11l9-8 9 8"/><path d="M5 10v10h14V10"/></symbol>
   <symbol id="i-layers" viewBox="0 0 24 24"><path d="M12 3l9 5-9 5-9-5 9-5z"/><path d="M3 13l9 5 9-5"/></symbol>
   <symbol id="i-target" viewBox="0 0 24 24"><circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></symbol>
   <symbol id="i-pump" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/><path d="M10 8l6 4-6 4z"/></symbol>
   <symbol id="i-warning" viewBox="0 0 24 24"><path d="M12 3l10 18H2L12 3z"/><path d="M12 9v5"/><circle cx="12" cy="17" r="1"/></symbol>
   <symbol id="i-clock" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/><path d="M12 7v5l3 2"/></symbol>
   <symbol id="i-sun" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/></symbol>
   <symbol id="i-moon" viewBox="0 0 24 24"><path d="M20 15.5A8.5 8.5 0 0 1 8.5 4 8.5 8.5 0 1 0 20 15.5z"/></symbol>
   <symbol id="i-mqtt" viewBox="0 0 24 24"><circle cx="12" cy="12" r="2.5"/><circle cx="12" cy="4" r="1.5"/><circle cx="5" cy="19" r="1.5"/><circle cx="19" cy="19" r="1.5"/><path d="M12 6.5v3M10 13.5l-3.5 4.3M14 13.5l3.5 4.3"/></symbol>
</svg>

<main>
  <?lsp=app.ui_header{title="Тёплый пол", subtitle="Xedge32 · насос и датчики DS18B20", active="overview"}?>

  <div class="view-controls page-tools">
    <span id="mqttStatus" class="mqtt-status" role="status" aria-live="polite" hidden>
      <svg class="icon" aria-hidden="true"><use href="#i-mqtt"/></svg>
    </span>
    <button id="viewToggle" class="view-toggle" type="button">Компактный вид</button>
  </div>

  <section class="card clock-card" aria-label="Текущее время">
    <div id="lcdClock" class="lcd-clock" role="timer" aria-label="Текущее время"></div>
  </section>

  <section id="banner" class="banner hidden"></section>

  <section class="status-strip compact-only" aria-label="Статус">
    <span id="stPump" class="status-pill">
      <svg class="icon" aria-hidden="true"><use href="#i-pump"/></svg>
      <span id="stPumpText">—</span>
    </span>
    <span id="stFault" class="status-pill fault" hidden>
      <svg class="icon" aria-hidden="true"><use href="#i-warning"/></svg>
      <span>Авария</span>
    </span>
    <span id="stOverride" class="status-pill" hidden>
      <svg class="icon" aria-hidden="true"><use href="#i-clock"/></svg>
      <span id="stOverrideText">Override</span>
    </span>
  </section>

  <section class="grid">
    <article class="card tile">
      <span class="label">
        <svg class="icon" aria-hidden="true"><use href="#i-house"/></svg>
        Помещение
      </span>
      <strong id="room" class="value">—</strong>
    </article>

    <article class="card tile">
      <span class="label">
        <svg class="icon" aria-hidden="true"><use href="#i-layers"/></svg>
        Пол
      </span>
      <strong id="floor" class="value">—</strong>
      <span class="muted full-only">предел <span id="floorLimit">—</span> °C</span>
    </article>

    <article class="card tile target-tile">
      <span class="label">
        <svg class="icon" aria-hidden="true"><use href="#i-target"/></svg>
        Уставка
      </span>
      <strong id="target" class="value">—</strong>
      <span class="muted full-only">желаемая температура</span>
      <button id="targetTileButton" class="tile-open compact-only" type="button"
              aria-label="Изменить уставку" aria-controls="compactSetpoint"
              aria-haspopup="dialog" aria-expanded="false"></button>
    </article>

    <article class="card tile override-tile">
      <span class="label">
        <svg class="icon" aria-hidden="true"><use href="#i-clock"/></svg>
        Текущая уставка
      </span>
      <p class="override-schedule">
        <span id="overrideUntil">—</span><br>
        <span id="overrideAfter">—</span>
      </p>
    </article>

    <article class="card tile">
      <span class="label">
        <svg class="icon" aria-hidden="true"><use href="#i-pump"/></svg>
        Насос
      </span>
      <strong id="pump" class="value">—</strong>
      <span id="pumpHours" class="muted full-only">наработка —</span>
      <span id="reason" class="muted full-only"></span>
    </article>
  </section>

  <section id="compactSetpoint" class="compact-setpoint" hidden>
    <div class="compact-setpoint-panel card" role="dialog" aria-modal="true" aria-labelledby="compactSetpointTitle">
      <div class="compact-setpoint-head">
        <h2 id="compactSetpointTitle">Уставка</h2>
        <button id="closeCompactSetpoint" class="compact-setpoint-close" type="button" aria-label="Закрыть">×</button>
      </div>
      <div class="compact-editor" role="group" aria-label="Желаемая температура">
        <button id="minusTarget" class="step-btn" type="button" aria-label="Уменьшить уставку">−</button>
        <div class="compact-target">
          <span id="compactTarget">—</span><span class="unit">°C</span>
          <small id="compactHint">новый override на 3 ч</small>
        </div>
        <button id="plusTarget" class="step-btn" type="button" aria-label="Увеличить уставку">+</button>
      </div>
      <div class="compact-editor compact-duration-editor" role="group" aria-label="Время override">
        <button id="minusDuration" class="step-btn small" type="button" aria-label="Уменьшить время override">−</button>
        <div class="compact-duration">
          <span id="compactDuration">3 ч</span>
          <small>время override</small>
        </div>
        <button id="plusDuration" class="step-btn small" type="button" aria-label="Увеличить время override">+</button>
      </div>
      <div class="compact-actions">
        <button id="clearOverrideCompact" class="secondary" type="button">Сбросить override</button>
        <span id="compactSetpointResult" class="muted"></span>
      </div>
    </div>
  </section>

  <section class="card full-only">
    <h2>Желаемая температура</h2>
    <form id="setpointForm" class="row">
      <input id="setpoint" type="number" min="16" max="28" step="0.5" required>
      <button type="submit">Задать на 2 часа</button>
      <button id="clearOverride" type="button" class="secondary">Снять override</button>
    </form>
    <p id="setpointResult" class="muted"></p>
    <p id="overrideInfo" class="muted"></p>
  </section>

  <details id="details" class="card details-card">
    <summary class="compact-only">Подробнее: подача, датчики, диагностика</summary>
    <div class="details-body">
      <section class="subcard">
        <h2>Подача / обратка</h2>
        <div class="detail-row">
          <span>Подача: <strong id="supply">—</strong></span>
          <span>Обратка: <strong id="returnTemp">—</strong></span>
          <span>Моточасы: <strong id="pumpHoursDetail">—</strong></span>
        </div>
      </section>

      <section class="subcard">
        <h2>Датчики</h2>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Роль</th><th>Метка</th><th>Шина</th><th>Температура</th><th>Статус</th></tr></thead>
            <tbody id="sensors"></tbody>
          </table>
        </div>
      </section>

      <section class="subcard">
        <h2>Диагностика</h2>
        <pre id="diagnostics" class="muted"></pre>
      </section>
    </div>
  </details>
</main>

<script>
const $ = id => document.getElementById(id);
const fmt = v => (v === null || v === undefined) ? '—' : Number(v).toFixed(1) + ' °C';
const fmtShort = v => (v === null || v === undefined) ? '—' : Number(v).toFixed(1);
const asArray = v => Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []);
const VIEW_KEY = 'thermostat.view';
const DEFAULT_SETPOINT_MIN = 16;
const DEFAULT_SETPOINT_MAX = 28;
const SETPOINT_IDLE_MS = 60000;
const OVERRIDE_STEP_MINUTES = 30;
const DEFAULT_OVERRIDE_MINUTES = 180;
const DEFAULT_OVERRIDE_MAX_MINUTES = 360;
let lastState = null;
let pendingTarget = null;
let saveTimer = null;
let setpointOpener = null;
let setpointIdleTimer = null;
let overrideMinutes = DEFAULT_OVERRIDE_MINUTES;

const SEGMENTS = {
   '0': 'abcdef',
   '1': 'bc',
   '2': 'abged',
   '3': 'abgcd',
   '4': 'fgbc',
   '5': 'afgcd',
   '6': 'afgecd',
   '7': 'abc',
   '8': 'abcdefg',
   '9': 'abcdfg',
   '-': 'g'
};

const clock = $('lcdClock');
let clockBase = null;

function makeDigit() {
   const digit = document.createElement('div');
   digit.className = 'lcd-digit';
   for (const name of ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
      const segment = document.createElement('span');
      segment.className = 'lcd-seg seg-' + name;
      segment.dataset.seg = name;
      digit.appendChild(segment);
   }
   return digit;
}

const clockHoursHigh = makeDigit();
const clockHoursLow = makeDigit();
const clockMinutesHigh = makeDigit();
const clockMinutesLow = makeDigit();
const clockColon = document.createElement('div');
clockColon.className = 'lcd-colon';
clockColon.setAttribute('aria-hidden', 'true');
clockColon.innerHTML = '<span></span><span></span>';
clock.append(clockHoursHigh, clockHoursLow, clockColon, clockMinutesHigh, clockMinutesLow);
const clockDigits = [clockHoursHigh, clockHoursLow, clockMinutesHigh, clockMinutesLow];

function setDigit(element, character) {
   const active = SEGMENTS[character] || '';
   for (const segment of element.children) {
      segment.classList.toggle('on', active.indexOf(segment.dataset.seg) !== -1);
   }
}

function syncClock(state) {
   if (!state || typeof state.time !== 'number') return;
   clockBase = {
      epoch: state.time,
      offset: Number(state.utc_offset_minutes) || 0,
      syncedAt: Date.now(),
      valid: state.time_valid !== false
   };
}

function updateClock() {
   if (!clockBase || !clockBase.valid) {
      clockDigits.forEach(element => setDigit(element, '-'));
      clock.classList.add('invalid');
      clock.setAttribute('aria-label', 'Время не синхронизировано');
      return;
   }
   const elapsed = Math.floor((Date.now() - clockBase.syncedAt) / 1000);
   const stamp = new Date((clockBase.epoch + elapsed + clockBase.offset * 60) * 1000);
   const hours = String(stamp.getUTCHours()).padStart(2, '0');
   const minutes = String(stamp.getUTCMinutes()).padStart(2, '0');
   setDigit(clockHoursHigh, hours[0]);
   setDigit(clockHoursLow, hours[1]);
   setDigit(clockMinutesHigh, minutes[0]);
   setDigit(clockMinutesLow, minutes[1]);
   clock.classList.remove('invalid');
   const label = 'Текущее время ' + hours + ':' + minutes;
   if (clock.getAttribute('aria-label') !== label) clock.setAttribute('aria-label', label);
}

setInterval(updateClock, 1000);

function viewMode() {
   return document.documentElement.dataset.view === 'compact' ? 'compact' : 'full';
}

function applyView(mode, persist) {
   if (mode !== 'compact') closeCompactSetpoint(false);
   document.documentElement.dataset.view = mode;
   const button = $('viewToggle');
   const details = $('details');
   if (details) details.open = mode === 'full';
   if (button) {
      button.textContent = mode === 'compact' ? 'Полный вид' : 'Компактный вид';
      button.setAttribute('aria-label', mode === 'compact' ? 'Переключить на полный вид' : 'Переключить на компактный вид');
   }
   if (persist) {
      try { localStorage.setItem(VIEW_KEY, mode); } catch (e) {}
   }
}

function storedView() {
   try {
      const value = localStorage.getItem(VIEW_KEY);
      return value === 'compact' || value === 'full' ? value : null;
   } catch (e) {
      return null;
   }
}

function resetSetpointIdleTimer() {
   clearTimeout(setpointIdleTimer);
   setpointIdleTimer = null;
   const sheet = $('compactSetpoint');
   if (!sheet || sheet.hidden) return;
   setpointIdleTimer = setTimeout(() => {
      setpointIdleTimer = null;
      closeCompactSetpoint();
   }, SETPOINT_IDLE_MS);
}

function openCompactSetpoint() {
   if (viewMode() !== 'compact') return;
   const sheet = $('compactSetpoint');
   if (!sheet || !sheet.hidden) return;
   setpointOpener = $('targetTileButton');
   if (lastState) $('compactTarget').textContent = fmtShort(lastState.target);
   if (lastState && lastState.override_active && lastState.override_until) {
      const remaining = Math.max(0, Number(lastState.override_until) - Number(lastState.time || 0));
      setOverrideMinutes(Math.ceil(remaining / 60 / OVERRIDE_STEP_MINUTES) * OVERRIDE_STEP_MINUTES);
   } else {
      setOverrideMinutes(DEFAULT_OVERRIDE_MINUTES);
   }
   sheet.hidden = false;
   sheet.classList.add('is-open');
   document.body.classList.add('setpoint-open');
   $('targetTileButton').setAttribute('aria-expanded', 'true');
   $('closeCompactSetpoint').focus({preventScroll: true});
   resetSetpointIdleTimer();
}

function closeCompactSetpoint(restoreFocus = true) {
   const sheet = $('compactSetpoint');
   if (!sheet || sheet.hidden) return;
   clearTimeout(setpointIdleTimer);
   setpointIdleTimer = null;
   sheet.classList.remove('is-open');
   sheet.hidden = true;
   document.body.classList.remove('setpoint-open');
   $('targetTileButton').setAttribute('aria-expanded', 'false');
   if (restoreFocus && setpointOpener && document.contains(setpointOpener)) {
      setpointOpener.focus({preventScroll: true});
   }
   setpointOpener = null;
}

function setpointBounds() {
   const stateMin = lastState ? Number(lastState.setpoint_min) : NaN;
   const stateMax = lastState ? Number(lastState.setpoint_max) : NaN;
   return {
      min: Number.isFinite(stateMin) ? stateMin : DEFAULT_SETPOINT_MIN,
      max: Number.isFinite(stateMax) ? stateMax : DEFAULT_SETPOINT_MAX
   };
}

function clampTarget(value) {
   const bounds = setpointBounds();
   return Math.min(bounds.max, Math.max(bounds.min, roundHalf(value)));
}

function showSetpointMessage(text) {
   if ($('setpointResult')) $('setpointResult').textContent = text;
   if ($('compactSetpointResult')) $('compactSetpointResult').textContent = text;
}

function roundHalf(value) {
   return Math.round(value * 2) / 2;
}

function maxOverrideMinutes() {
   const value = lastState ? Number(lastState.override_max_minutes) : NaN;
   return Number.isFinite(value) && value >= OVERRIDE_STEP_MINUTES
      ? value
      : DEFAULT_OVERRIDE_MAX_MINUTES;
}

function formatOverrideDuration(minutes) {
   const total = Math.max(OVERRIDE_STEP_MINUTES,
      Math.round(minutes / OVERRIDE_STEP_MINUTES) * OVERRIDE_STEP_MINUTES);
   const hours = Math.floor(total / 60);
   const mins = total % 60;
   if (hours && mins) return hours + ' ч ' + mins + ' мин';
   if (hours) return hours + ' ч';
   return mins + ' мин';
}

function clampOverrideMinutes(value) {
   const rounded = Math.round(value / OVERRIDE_STEP_MINUTES) * OVERRIDE_STEP_MINUTES;
   return Math.min(maxOverrideMinutes(), Math.max(OVERRIDE_STEP_MINUTES, rounded));
}

function renderOverrideMinutes() {
   if ($('compactDuration')) $('compactDuration').textContent = formatOverrideDuration(overrideMinutes);
   if ((!lastState || !lastState.override_active) && $('compactHint')) {
      $('compactHint').textContent = 'новый override на ' + formatOverrideDuration(overrideMinutes);
   }
}

function setOverrideMinutes(value) {
   overrideMinutes = clampOverrideMinutes(value);
   renderOverrideMinutes();
}

function scheduleOverrideSave() {
   showSetpointMessage('Сохранение…');
   clearTimeout(saveTimer);
   saveTimer = setTimeout(saveTarget, 2200);
}

function scheduleTargetSave(value) {
   const target = clampTarget(value);
   pendingTarget = target;
   if ($('compactTarget')) $('compactTarget').textContent = fmtShort(target);
   if (document.activeElement !== $('setpoint')) $('setpoint').value = target;
   scheduleOverrideSave();
}

async function saveTarget() {
   saveTimer = null;
   const target = pendingTarget !== null ? pendingTarget : (lastState && lastState.target);
   if (target === null || target === undefined) return;
   const minutes = clampOverrideMinutes(overrideMinutes);
   overrideMinutes = minutes;
   renderOverrideMinutes();
   try {
      const r = await fetch('api/setpoint.lsp', {
         method: 'POST',
         headers: {'Content-Type': 'application/x-www-form-urlencoded'},
         body: 'target=' + encodeURIComponent(target) + '&hours=' + encodeURIComponent(minutes / 60)
      });
      const data = await r.json();
      if (data.ok) {
         pendingTarget = null;
         showSetpointMessage('Уставка принята: ' + fmt(data.target) + ' на ' + formatOverrideDuration(minutes));
      } else {
         pendingTarget = null;
         showSetpointMessage('Ошибка: ' + (data.error || ''));
      }
   } catch (e) {
      pendingTarget = null;
      showSetpointMessage('Ошибка: ' + e);
   }
   refresh();
}

function clearOverride() {
   clearTimeout(saveTimer);
   saveTimer = null;
   pendingTarget = null;
   return fetch('api/setpoint.lsp', {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'clear=1'
   }).then(r => r.json()).then(data => {
      showSetpointMessage(data.ok ? ('Override снят, цель: ' + fmt(data.target)) : ('Ошибка: ' + (data.error || '')));
      refresh();
   }).catch(e => showSetpointMessage('Ошибка: ' + e));
}

async function refresh() {
   try {
      const r = await fetch('api/state.lsp', {cache: 'no-store'});
      const s = await r.json();
      lastState = s;
      syncClock(s);
      updateClock();
      const bounds = setpointBounds();
      $('setpoint').min = bounds.min;
      $('setpoint').max = bounds.max;
      const compact = viewMode() === 'compact';

      $('pump').textContent = s.pump ? 'ВКЛ' : 'ВЫКЛ';
      $('pump').className = 'value ' + (s.pump ? 'on' : 'off');
      $('reason').textContent = s.last_reason || '';
      const pumpHours = typeof s.pump_hours === 'number' ? s.pump_hours.toFixed(1) + ' ч' : '—';
      $('pumpHours').textContent = 'наработка ' + pumpHours;
      if ($('pumpHoursDetail')) $('pumpHoursDetail').textContent = pumpHours;
      $('room').textContent = fmt(s.room);
      $('floor').textContent = fmt(s.floor);
      $('supply').textContent = fmt(s.supply);
      $('returnTemp').textContent = fmt(s.return_temp);
      $('target').textContent = fmtShort(s.target);
      $('floorLimit').textContent = fmtShort(s.floor_limit);
      if (document.activeElement !== $('setpoint') && saveTimer === null && pendingTarget === null) {
         $('setpoint').value = s.target ?? '';
      }
      if (saveTimer === null && pendingTarget === null && $('compactTarget')) {
         $('compactTarget').textContent = fmtShort(s.target);
      }

      const overrideActive = !!s.override_active;
      if (overrideActive && s.override_until) {
         const until = new Date(s.override_until * 1000);
         const untilShort = until.toLocaleTimeString([], {hour: '2-digit', minute: '2-digit', hour12: false});
         $('overrideInfo').textContent = 'Override действует до ' + untilShort;
         $('compactHint').textContent = 'override до ' + untilShort;
         $('stOverride').hidden = false;
         $('stOverrideText').textContent = 'до ' + untilShort;
         if ($('overrideUntil')) $('overrideUntil').textContent = 'действует до ' + untilShort;
         if ($('overrideAfter')) {
            $('overrideAfter').textContent = 'Затем — ' + fmt(s.override_after_target ?? s.base_target);
         }
      } else {
         $('overrideInfo').textContent = 'Override не активен; базовая уставка ' + fmt(s.base_target);
         renderOverrideMinutes();
         $('stOverride').hidden = true;
         if ($('overrideUntil')) $('overrideUntil').textContent = 'действует без ограничения';
         if ($('overrideAfter')) $('overrideAfter').textContent = 'Текущая — ' + fmt(s.target);
      }

      $('stPumpText').textContent = s.pump ? 'Насос ВКЛ' : 'Насос ВЫКЛ';
      $('stPump').className = 'status-pill ' + (s.pump ? 'on' : 'off');
      const mqtt = $('mqttStatus');
      if (s.mqtt_enabled) {
         const connected = !!s.mqtt_connected;
         const label = connected ? 'MQTT подключён' : 'MQTT не подключён';
         mqtt.hidden = false;
         mqtt.className = 'mqtt-status ' + (connected ? 'on' : 'fault');
         mqtt.setAttribute('aria-label', label);
         mqtt.title = label;
      } else {
         mqtt.hidden = true;
      }

      const faults = asArray(s.faults);
      const warnings = asArray(s.warnings);
      $('stFault').hidden = faults.length === 0;
      $('stFault').className = 'status-pill fault';

      const banner = $('banner');
      const problems = [];
      if (!s.ready) problems.push('Конфигурация датчиков не завершена — насос заблокирован.');
      if (s.pin_available === false) problems.push('Генератор ключей недоступен: вход по PIN отключён.');
      if (s.pin_configured === false) problems.push('PIN не задан. Настройка: /setup.lsp');
      if (!s.time_valid) problems.push('Время не синхронизировано — расписание неактивно.');
      if (faults.length) problems.push('Авария: ' + faults.join(', '));
      if (warnings.length) problems.push('Предупреждения: ' + warnings.join(', '));
      if (problems.length) {
         banner.textContent = compact && problems.length > 1 ? problems[0] + ' …' : problems.join(' ');
         banner.classList.remove('hidden');
      } else {
         banner.classList.add('hidden');
      }

      const tbody = $('sensors');
      tbody.textContent = '';
      for (const x of asArray(s.sensors)) {
         const tr = document.createElement('tr');
         const cells = [x.role, x.label || x.rom, x.bus, fmt(x.temp), x.ok ? 'OK' : (x.err || 'ошибка')];
         for (const c of cells) {
            const td = document.createElement('td');
            td.textContent = c ?? '';
            tr.appendChild(td);
         }
         tbody.appendChild(tr);
      }

      $('diagnostics').textContent = JSON.stringify({
         mode: s.mode, service_mode: s.service_mode, mqtt_enabled: s.mqtt_enabled,
         mqtt_connected: s.mqtt_connected, wifi: s.wifi, wifi_mode: s.wifi_mode,
         espnow_available: s.espnow_available, espnow_api: s.espnow_api,
         espnow_enabled: s.espnow_enabled, espnow_open: s.espnow_open,
         espnow_provision_active: s.espnow_provision_active,
         espnow_provision_remaining: s.espnow_provision_remaining,
         espnow_channel: s.espnow_channel, espnow_drops: s.espnow_drops,
         espnow_nodes: s.espnow_nodes, espnow_sensors: s.espnow_sensors,
         espnow_last_error: s.espnow_last_error,
         led_tick: s.led_tick, pin_configured: s.pin_configured,
         pin_available: s.pin_available, override_active: s.override_active,
         override_until: s.override_until, base_target: s.base_target,
         setpoint_min: s.setpoint_min, setpoint_max: s.setpoint_max,
         utc_offset_minutes: s.utc_offset_minutes, time_valid: s.time_valid
      }, null, 2);
   } catch (e) {
      $('banner').textContent = 'Нет связи с контроллером: ' + e;
      $('banner').classList.remove('hidden');
   }
}

applyView(storedView() || viewMode(), false);

$('viewToggle').addEventListener('click', () => {
   const next = viewMode() === 'compact' ? 'full' : 'compact';
   applyView(next, true);
   refresh();
});

$('targetTileButton').addEventListener('click', openCompactSetpoint);
$('closeCompactSetpoint').addEventListener('click', () => closeCompactSetpoint());
$('compactSetpoint').addEventListener('click', event => {
   if (event.target === event.currentTarget) closeCompactSetpoint();
});
['pointerdown', 'keydown', 'click', 'input'].forEach(type => {
   $('compactSetpoint').addEventListener(type, resetSetpointIdleTimer);
});

document.addEventListener('keydown', event => {
   const sheet = $('compactSetpoint');
   if (!sheet || sheet.hidden) return;
   if (event.key === 'Escape') {
      event.preventDefault();
      closeCompactSetpoint();
      return;
   }
   if (event.key !== 'Tab') return;
   const focusable = Array.from(sheet.querySelectorAll('button:not([disabled])'));
   if (!focusable.length) return;
   const first = focusable[0];
   const last = focusable[focusable.length - 1];
   if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
   } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
   }
});

$('minusTarget').addEventListener('click', () => {
   const base = pendingTarget !== null ? pendingTarget : (lastState && lastState.target) || 22;
   scheduleTargetSave(base - 0.5);
});

$('plusTarget').addEventListener('click', () => {
   const base = pendingTarget !== null ? pendingTarget : (lastState && lastState.target) || 22;
   scheduleTargetSave(base + 0.5);
});

$('minusDuration').addEventListener('click', () => {
   setOverrideMinutes(overrideMinutes - OVERRIDE_STEP_MINUTES);
   scheduleOverrideSave();
});

$('plusDuration').addEventListener('click', () => {
   setOverrideMinutes(overrideMinutes + OVERRIDE_STEP_MINUTES);
   scheduleOverrideSave();
});

$('setpointForm').addEventListener('submit', e => {
   e.preventDefault();
   clearTimeout(saveTimer);
   saveTimer = null;
   pendingTarget = null;
   const target = clampTarget(Number($('setpoint').value));
   fetch('api/setpoint.lsp', {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'target=' + encodeURIComponent(target)
   }).then(r => r.json()).then(data => {
      showSetpointMessage(data.ok ? ('Уставка принята на 2 часа: ' + fmt(data.target)) : ('Ошибка: ' + (data.error || '')));
      refresh();
   }).catch(e => showSetpointMessage('Ошибка: ' + e));
});

$('clearOverride').addEventListener('click', clearOverride);
$('clearOverrideCompact').addEventListener('click', clearOverride);

const media = window.matchMedia('(max-width: 640px)');
media.addEventListener('change', () => {
   if (!storedView()) applyView(media.matches ? 'compact' : 'full', false);
});

refresh();
setInterval(refresh, 2000);
</script>
</body>
</html>
