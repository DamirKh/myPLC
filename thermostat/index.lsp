<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Тёплый пол</title>
<link rel="stylesheet" href="static/style.css">
</head>
<body>
<main>
  <header>
    <div>
      <h1>Тёплый пол</h1>
      <p class="muted">Xedge32 · насос и датчики DS18B20</p>
    </div>
    <nav>
      <a href="history.lsp">История</a>
      <a href="settings.lsp">Настройки</a>
      <a href="sensors.lsp">Датчики</a>
    </nav>
  </header>

  <section id="banner" class="banner hidden"></section>

  <section class="grid">
    <article class="card">
      <span class="label">Насос</span>
      <strong id="pump" class="value">—</strong>
      <span id="reason" class="muted"></span>
    </article>
    <article class="card">
      <span class="label">Воздух</span>
      <strong id="room" class="value">—</strong>
      <span class="muted">цель <span id="target">—</span> °C</span>
    </article>
    <article class="card">
      <span class="label">Пол</span>
      <strong id="floor" class="value">—</strong>
      <span class="muted">предел <span id="floorLimit">—</span> °C</span>
    </article>
    <article class="card">
      <span class="label">Подача / обратка</span>
      <strong id="supply" class="value">—</strong>
      <span class="muted">обратка <span id="returnTemp">—</span> °C</span>
    </article>
  </section>

  <section class="card">
    <h2>Желаемая температура</h2>
    <form id="setpointForm" class="row">
      <input id="setpoint" type="number" min="16" max="28" step="0.5" required>
      <button type="submit">Задать на 2 часа</button>
      <button id="clearOverride" type="button" class="secondary">Снять override</button>
    </form>
    <p id="setpointResult" class="muted"></p>
  </section>

  <section class="card">
    <h2>Датчики</h2>
    <table>
      <thead><tr><th>Роль</th><th>Метка</th><th>Шина</th><th>Температура</th><th>Статус</th></tr></thead>
      <tbody id="sensors"></tbody>
    </table>
  </section>

  <section class="card">
    <h2>Диагностика</h2>
    <pre id="diagnostics" class="muted"></pre>
  </section>
</main>
<script>
const $ = id => document.getElementById(id);
const fmt = v => (v === null || v === undefined) ? '—' : Number(v).toFixed(1) + ' °C';
const asArray = v => Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []);

async function refresh() {
  try {
    const r = await fetch('api/state.lsp', {cache: 'no-store'});
    const s = await r.json();
    $('pump').textContent = s.pump ? 'ВКЛ' : 'ВЫКЛ';
    $('pump').className = 'value ' + (s.pump ? 'on' : 'off');
    $('reason').textContent = s.last_reason || '';
    $('room').textContent = fmt(s.room);
    $('floor').textContent = fmt(s.floor);
    $('supply').textContent = fmt(s.supply);
    $('returnTemp').textContent = fmt(s.return_temp);
    $('target').textContent = fmt(s.target).replace(' °C', '');
    $('floorLimit').textContent = fmt(s.floor_limit).replace(' °C', '');
    if (document.activeElement !== $('setpoint')) $('setpoint').value = s.target ?? '';
    const banner = $('banner');
    const problems = [];
    if (!s.ready) problems.push('Конфигурация датчиков не завершена — насос заблокирован.');
    if (!s.time_valid) problems.push('Время не синхронизировано — расписание неактивно.');
    const faults = asArray(s.faults);
    const warnings = asArray(s.warnings);
    if (faults.length) problems.push('Авария: ' + faults.join(', '));
    if (warnings.length) problems.push('Предупреждения: ' + warnings.join(', '));
    if (problems.length) {
      banner.textContent = problems.join(' ');
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
      time_valid: s.time_valid
    }, null, 2);
  } catch (e) {
    $('banner').textContent = 'Нет связи с контроллером: ' + e;
    $('banner').classList.remove('hidden');
  }
}

$('setpointForm').addEventListener('submit', async e => {
  e.preventDefault();
  const target = $('setpoint').value;
  const r = await fetch('api/setpoint.lsp', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'target=' + encodeURIComponent(target)
  });
  const data = await r.json();
  $('setpointResult').textContent = data.ok ? 'Уставка принята' : ('Ошибка: ' + (data.error || ''));
  refresh();
});

$('clearOverride').addEventListener('click', async () => {
  await fetch('api/setpoint.lsp', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'clear=1'
  });
  refresh();
});

refresh();
setInterval(refresh, 2000);
</script>
</body>
</html>
