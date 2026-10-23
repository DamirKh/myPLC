<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>История — тёплый пол</title>
<script src="/static/theme.js"></script>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/style.css?v=9">
</head>
<body>
<main>
<header>
  <div><h1>История</h1><p class="muted">Температуры и наработка насоса</p></div>
  <nav><a href="/">Обзор</a><a href="/admin/settings.lsp">Настройки</a><a href="/admin/sensors.lsp">Датчики</a><a href="/admin/wifi.lsp">Wi-Fi</a></nav>
</header>

<section class="card">
  <div class="chart-head">
    <div>
      <h2>Сводка</h2>
      <p class="muted">Моточасы насоса: <strong id="pump-hours">—</strong></p>
    </div>
    <div id="history-status" class="muted"></div>
  </div>
</section>

<section class="card">
  <div class="chart-head">
    <div><h2>Комната</h2><p class="muted">Воздух и пол, используемые для управления</p></div>
    <div class="row">
      <button data-room-range="86400" class="secondary">24 часа</button>
      <button data-room-range="604800">7 дней</button>
    </div>
  </div>
  <canvas id="chart-room" width="1000" height="320" aria-label="Температура воздуха и пола"></canvas>
  <div class="chart-legend" id="legend-room"></div>
</section>

<section class="card">
  <div class="chart-head">
    <div><h2>Насос</h2><p class="muted">Подача, обратка, насос и остальные датчики diag</p></div>
    <div class="row">
      <button data-pump-mode="history">24 часа</button>
      <button data-pump-mode="live" class="secondary">Сейчас</button>
    </div>
  </div>
  <canvas id="chart-pump" width="1000" height="320" aria-label="Температуры вокруг насоса"></canvas>
  <div class="chart-legend" id="legend-pump"></div>
</section>

<section class="card">
  <div class="chart-head">
    <div><h2>Датчики</h2><p class="muted">Только текущие значения, без сохранения истории</p></div>
    <select id="sensor-bus" class="chart-select">
      <option value="diag">diag</option>
      <option value="control_a">control_a</option>
      <option value="control_b">control_b</option>
    </select>
  </div>
  <canvas id="chart-sensors" width="1000" height="320" aria-label="Текущие температуры датчиков"></canvas>
  <div class="chart-legend" id="legend-sensors"></div>
</section>
</main>
<script>
const asArray = v => Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []);
const roleNames = {
  room: 'воздух',
  floor: 'пол',
  supply: 'подача',
  return: 'обратка',
  pump: 'насос',
  extra: 'прочее'
};
const LIVE_WINDOW_SEC = 600;

const roomCanvas = document.getElementById('chart-room');
const pumpCanvas = document.getElementById('chart-pump');
const sensorsCanvas = document.getElementById('chart-sensors');
const roomLegend = document.getElementById('legend-room');
const pumpLegend = document.getElementById('legend-pump');
const sensorsLegend = document.getElementById('legend-sensors');
const statusLine = document.getElementById('history-status');
const pumpHoursLine = document.getElementById('pump-hours');
const busSelect = document.getElementById('sensor-bus');

let roomRange = 604800;
let pumpMode = 'history';
let currentBus = busSelect.value;
let roomItems = [];
let pumpItems = [];
let stateSensors = [];
let pumpHours = null;
let live = new Map();
let lastStateTime = null;

function themeColor(name, fallback) {
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return value || fallback;
}

function paletteColor(index) {
  const fallbacks = ['#2563eb', '#f59e0b', '#dc2626', '#16a34a', '#9333ea', '#0891b2', '#db2777', '#64748b'];
  return themeColor('--chart-' + ((index % 8) + 1), fallbacks[index % 8]);
}

function sensorMeta(key) {
  const found = stateSensors.find(item => item.key === key);
  if (found) return found;
  const split = key.indexOf(':');
  return {
    key,
    bus: split >= 0 ? key.slice(0, split) : '',
    rom: split >= 0 ? key.slice(split + 1) : key,
    role: '',
    label: ''
  };
}

function sensorName(meta) {
  if (meta.label && String(meta.label).trim()) {
    return String(meta.label).trim() + ' · ' + meta.rom;
  }
  if (meta.role && roleNames[meta.role]) {
    return roleNames[meta.role] + ' · ' + meta.rom;
  }
  return meta.rom;
}

function fmtTemp(value) {
  return typeof value === 'number' ? value.toFixed(2) + ' °C' : '—';
}

function fmtHours(value) {
  return typeof value === 'number' ? value.toFixed(1) + ' ч' : '—';
}

function latestValue(series) {
  if (!series.values.length) return null;
  return series.values[series.values.length - 1].v;
}

function seriesWithValues(series) {
  return series.filter(item => item.values && item.values.length > 0);
}

function drawChart(canvas, series, xRange) {
  const ctx = canvas.getContext('2d');
  const w = canvas.width;
  const h = canvas.height;
  const left = 52;
  const right = 14;
  const top = 18;
  const bottom = 28;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = themeColor('--surface', '#fff');
  ctx.fillRect(0, 0, w, h);

  const visible = seriesWithValues(series);
  if (!visible.length) {
    ctx.fillStyle = themeColor('--muted', '#5b667a');
    ctx.font = '14px sans-serif';
    ctx.fillText('Нет данных', left, 34);
    return;
  }

  const chartW = w - left - right;
  const chartH = h - top - bottom;
  let t0;
  let t1;
  if (xRange) {
    t0 = xRange.t0;
    t1 = xRange.t1;
  } else {
    const times = [];
    for (const item of visible) {
      for (const point of item.values) times.push(point.t);
    }
    t0 = Math.min(...times);
    t1 = Math.max(...times);
  }
  if (t1 <= t0) {
    t0 -= 1800;
    t1 += 1800;
  }
  const values = [];
  for (const item of visible) {
    for (const point of item.values) values.push(point.v);
  }
  let v0 = Math.min(...values);
  let v1 = Math.max(...values);
  const pad = Math.max(0.8, (v1 - v0) * 0.12);
  v0 -= pad;
  v1 += pad;
  const xOf = t => left + (t - t0) / Math.max(1, t1 - t0) * chartW;
  const yOf = v => top + (v1 - v) / Math.max(0.1, v1 - v0) * chartH;

  ctx.strokeStyle = themeColor('--chart-grid', '#d7dee8');
  ctx.fillStyle = themeColor('--muted', '#5b667a');
  ctx.font = '12px sans-serif';
  ctx.lineWidth = 1;
  for (let i = 0; i <= 4; i++) {
    const y = top + i * chartH / 4;
    ctx.beginPath();
    ctx.moveTo(left, y);
    ctx.lineTo(w - right, y);
    ctx.stroke();
    ctx.fillText((v1 - i * (v1 - v0) / 4).toFixed(1) + '°', 6, y + 4);
  }

  const span = t1 - t0;
  const formatTime = t => {
    const date = new Date(t * 1000);
    if (span <= 86400) {
      return date.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
    }
    return date.toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit' });
  };
  for (let i = 0; i <= 3; i++) {
    const t = t0 + i * span / 3;
    ctx.fillStyle = themeColor('--muted', '#5b667a');
    ctx.textAlign = i === 0 ? 'left' : (i === 3 ? 'right' : 'center');
    ctx.fillText(formatTime(t), xOf(t), h - 8);
  }
  ctx.textAlign = 'left';

  for (const item of visible) {
    ctx.strokeStyle = item.color;
    ctx.lineWidth = item.width || 2;
    ctx.setLineDash(item.dashed ? [6, 4] : []);
    ctx.beginPath();
    let started = false;
    for (const point of item.values) {
      const px = xOf(point.t);
      const py = yOf(point.v);
      if (!started) {
        ctx.moveTo(px, py);
        started = true;
      } else {
        ctx.lineTo(px, py);
      }
    }
    ctx.stroke();
    if (item.values.length === 1) {
      ctx.fillStyle = item.color;
      ctx.beginPath();
      ctx.arc(xOf(item.values[0].t), yOf(item.values[0].v), 3, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.setLineDash([]);
}

function renderLegend(container, series, showCurrent) {
  container.textContent = '';
  for (const item of seriesWithValues(series)) {
    const row = document.createElement('span');
    row.className = 'chart-legend-item';
    const swatch = document.createElement('span');
    swatch.className = 'chart-swatch';
    swatch.style.background = item.dashed
      ? 'repeating-linear-gradient(90deg, ' + item.color + ' 0 4px, transparent 4px 7px)'
      : item.color;
    const label = document.createElement('span');
    label.textContent = item.label + (showCurrent ? ' — ' + fmtTemp(latestValue(item)) : '');
    row.appendChild(swatch);
    row.appendChild(label);
    container.appendChild(row);
  }
}

function roomSeries() {
  return [
    {
      key: 'room',
      label: 'Воздух (среднее)',
      color: themeColor('--chart-room', '#2563eb'),
      values: roomItems.filter(item => typeof item.room === 'number').map(item => ({ t: item.t, v: item.room }))
    },
    {
      key: 'floor',
      label: 'Пол (максимум)',
      color: themeColor('--chart-floor', '#f59e0b'),
      values: roomItems.filter(item => typeof item.floor === 'number').map(item => ({ t: item.t, v: item.floor }))
    },
    {
      key: 'target',
      label: 'Уставка',
      color: themeColor('--chart-target', '#64748b'),
      dashed: true,
      width: 1.5,
      values: roomItems.filter(item => typeof item.target === 'number').map(item => ({ t: item.t, v: item.target }))
    }
  ];
}

function pumpHistorySeries() {
  const keys = new Set();
  for (const item of pumpItems) {
    for (const key of Object.keys(item.sensors || {})) keys.add(key);
  }
  const metas = Array.from(keys).map(sensorMeta);
  metas.sort((a, b) => sensorName(a).localeCompare(sensorName(b), 'ru'));
  return metas.map((meta, index) => ({
    key: meta.key,
    label: sensorName(meta),
    color: paletteColor(index),
    values: pumpItems
      .filter(item => item.sensors && typeof item.sensors[meta.key] === 'number')
      .map(item => ({ t: item.t, v: item.sensors[meta.key] }))
  }));
}

function liveSeries(bus) {
  const metas = stateSensors.filter(meta => meta.bus === bus);
  metas.sort((a, b) => sensorName(a).localeCompare(sensorName(b), 'ru'));
  return metas.map((meta, index) => ({
    key: meta.key,
    label: sensorName(meta),
    color: paletteColor(index),
    values: live.get(meta.key) || []
  }));
}

function liveRange() {
  const now = lastStateTime || Math.floor(Date.now() / 1000);
  return { t0: now - LIVE_WINDOW_SEC, t1: now };
}

function renderRoom() {
  const series = roomSeries();
  drawChart(roomCanvas, series);
  renderLegend(roomLegend, series, false);
}

function renderPump() {
  const isLive = pumpMode === 'live';
  const series = isLive ? liveSeries('diag') : pumpHistorySeries();
  drawChart(pumpCanvas, series, isLive ? liveRange() : null);
  renderLegend(pumpLegend, series, isLive);
}

function renderSensors() {
  const series = liveSeries(currentBus);
  drawChart(sensorsCanvas, series, liveRange());
  renderLegend(sensorsLegend, series, true);
}

function renderAll() {
  renderRoom();
  renderPump();
  renderSensors();
}

function setRoomRangeButtons() {
  document.querySelectorAll('button[data-room-range]').forEach(button => {
    button.classList.toggle('secondary', Number(button.dataset.roomRange) !== roomRange);
  });
}

function setPumpModeButtons() {
  document.querySelectorAll('button[data-pump-mode]').forEach(button => {
    button.classList.toggle('secondary', button.dataset.pumpMode !== pumpMode);
  });
}

function applyState(data) {
  stateSensors = asArray(data.sensors);
  pumpHours = data.pump_hours;
  pumpHoursLine.textContent = fmtHours(pumpHours);
  const now = data.time || Math.floor(Date.now() / 1000);
  lastStateTime = now;
  for (const sensor of stateSensors) {
    if (!sensor.ok || typeof sensor.temp !== 'number') continue;
    let points = live.get(sensor.key);
    if (!points) {
      points = [];
      live.set(sensor.key, points);
    }
    if (points.length && points[points.length - 1].t === now) {
      points[points.length - 1].v = sensor.temp;
    } else {
      points.push({ t: now, v: sensor.temp });
    }
    while (points.length && points[0].t < now - LIVE_WINDOW_SEC) points.shift();
  }
}

async function loadStored() {
  statusLine.textContent = 'Загрузка…';
  try {
    const [roomResponse, pumpResponse, stateResponse] = await Promise.all([
      fetch('api/history.lsp?kind=room&range=' + roomRange, { cache: 'no-store' }),
      fetch('api/history.lsp?kind=pump&range=86400', { cache: 'no-store' }),
      fetch('api/state.lsp', { cache: 'no-store' })
    ]);
    const roomData = await roomResponse.json();
    const pumpData = await pumpResponse.json();
    const stateData = await stateResponse.json();
    roomItems = asArray(roomData.items);
    pumpItems = asArray(pumpData.items);
    applyState(stateData);
    statusLine.textContent = '';
    renderAll();
  } catch (error) {
    statusLine.textContent = 'Не удалось загрузить историю.';
  }
}

async function pollState() {
  try {
    const response = await fetch('api/state.lsp', { cache: 'no-store' });
    if (!response.ok) return;
    applyState(await response.json());
    renderPump();
    renderSensors();
  } catch (error) {
  }
}

document.querySelectorAll('button[data-room-range]').forEach(button => {
  button.addEventListener('click', () => {
    roomRange = Number(button.dataset.roomRange);
    setRoomRangeButtons();
    loadStored();
  });
});
document.querySelectorAll('button[data-pump-mode]').forEach(button => {
  button.addEventListener('click', () => {
    pumpMode = button.dataset.pumpMode;
    setPumpModeButtons();
    renderPump();
  });
});
busSelect.addEventListener('change', () => {
  currentBus = busSelect.value;
  renderSensors();
});
document.addEventListener('thermostat:theme', renderAll);
setRoomRangeButtons();
setPumpModeButtons();
loadStored();
setInterval(pollState, 2000);
</script>
</body>
</html>
