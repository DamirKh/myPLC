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
  <div><h1>История</h1><p class="muted">Температуры за выбранный период</p></div>
  <nav><a href="/">Обзор</a><a href="/admin/settings.lsp">Настройки</a><a href="/admin/sensors.lsp">Датчики</a><a href="/admin/wifi.lsp">Wi-Fi</a></nav>
</header>

<section class="card">
  <div class="chart-head">
    <div><h2>Период</h2><p class="muted">Данные хранятся в памяти и во flash</p></div>
    <div class="row">
      <button data-range="3600" class="secondary">1 час</button>
      <button data-range="86400" class="secondary">24 часа</button>
      <button data-range="604800" class="secondary">7 дней</button>
    </div>
  </div>
  <p id="history-status" class="muted"></p>
</section>

<section class="card">
  <div class="chart-head">
    <div><h2>Комната</h2><p class="muted">Температура воздуха и пола, используемая для управления</p></div>
  </div>
  <canvas id="chart-room" width="1000" height="320" aria-label="Температура воздуха и пола"></canvas>
  <div class="chart-legend" id="legend-room"></div>
</section>

<section class="card">
  <div class="chart-head">
    <div><h2>Насос</h2><p class="muted">Подача, обратка и насос</p></div>
  </div>
  <canvas id="chart-pump" width="1000" height="320" aria-label="Температуры диагностической линии"></canvas>
  <div class="chart-legend" id="legend-pump"></div>
</section>

<section class="card">
  <div class="chart-head">
    <div><h2>Датчики</h2><p class="muted">Все датчики выбранной шины</p></div>
    <select id="sensor-bus" class="chart-select">
      <option value="diag">diag</option>
      <option value="control_a">control_a</option>
      <option value="control_b">control_b</option>
    </select>
  </div>
  <canvas id="chart-sensors" width="1000" height="320" aria-label="Температуры датчиков выбранной шины"></canvas>
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

const roomCanvas = document.getElementById('chart-room');
const pumpCanvas = document.getElementById('chart-pump');
const sensorsCanvas = document.getElementById('chart-sensors');
const roomLegend = document.getElementById('legend-room');
const pumpLegend = document.getElementById('legend-pump');
const sensorsLegend = document.getElementById('legend-sensors');
const statusLine = document.getElementById('history-status');
const busSelect = document.getElementById('sensor-bus');

let currentRange = 86400;
let currentBus = busSelect.value;
let items = [];
let stateSensors = [];
const hiddenSensors = new Set();

function themeColor(name, fallback) {
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return value || fallback;
}

function paletteColor(index) {
  const fallbacks = ['#2563eb', '#f59e0b', '#dc2626', '#16a34a', '#9333ea', '#0891b2', '#db2777', '#64748b'];
  return themeColor('--chart-' + ((index % 8) + 1), fallbacks[index % 8]);
}

function valuePoints(key, mapper) {
  const out = [];
  for (const item of items) {
    const value = mapper(item);
    if (typeof value === 'number') out.push({ t: item.t, v: value });
  }
  return out;
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

function seriesWithValues(series) {
  return series.filter(item => item.values && item.values.length > 0);
}

function drawChart(canvas, series) {
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
  if (!items.length || !visible.length) {
    ctx.fillStyle = themeColor('--muted', '#5b667a');
    ctx.font = '14px sans-serif';
    ctx.fillText('Нет данных', left, 34);
    return;
  }

  const chartW = w - left - right;
  const chartH = h - top - bottom;
  const times = items.map(item => item.t);
  const t0 = Math.min(...times);
  const t1 = Math.max(...times);
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
    const value = v1 - i * (v1 - v0) / 4;
    ctx.fillText(value.toFixed(1) + '°', 6, y + 4);
  }

  const formatTime = t => {
    const date = new Date(t * 1000);
    if (currentRange <= 86400) {
      return date.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
    }
    return date.toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit' });
  };
  for (let i = 0; i <= 3; i++) {
    const t = t0 + i * (t1 - t0) / 3;
    const x = xOf(t);
    ctx.fillStyle = themeColor('--muted', '#5b667a');
    ctx.textAlign = i === 0 ? 'left' : (i === 3 ? 'right' : 'center');
    ctx.fillText(formatTime(t), x, h - 8);
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

function renderStaticLegend(container, series) {
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
    label.textContent = item.label;
    row.appendChild(swatch);
    row.appendChild(label);
    container.appendChild(row);
  }
}

function renderSensorLegend(series) {
  sensorsLegend.textContent = '';
  for (const item of seriesWithValues(series)) {
    const row = document.createElement('label');
    row.className = 'chart-legend-item';
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = !hiddenSensors.has(item.key);
    checkbox.addEventListener('change', () => {
      if (checkbox.checked) hiddenSensors.delete(item.key);
      else hiddenSensors.add(item.key);
      renderAll();
    });
    const swatch = document.createElement('span');
    swatch.className = 'chart-swatch';
    swatch.style.background = item.color;
    const label = document.createElement('span');
    label.textContent = item.label;
    row.appendChild(checkbox);
    row.appendChild(swatch);
    row.appendChild(label);
    sensorsLegend.appendChild(row);
  }
}

function roomSeries() {
  return [
    {
      key: 'room',
      label: 'Воздух (среднее)',
      color: themeColor('--chart-room', '#2563eb'),
      values: valuePoints('room', item => item.room)
    },
    {
      key: 'floor',
      label: 'Пол (максимум)',
      color: themeColor('--chart-floor', '#f59e0b'),
      values: valuePoints('floor', item => item.floor)
    },
    {
      key: 'target',
      label: 'Уставка',
      color: themeColor('--chart-target', '#64748b'),
      dashed: true,
      width: 1.5,
      values: valuePoints('target', item => item.target)
    }
  ];
}

function pumpSeries() {
  return [
    {
      key: 'supply',
      label: 'Подача',
      color: themeColor('--chart-supply', '#dc2626'),
      values: valuePoints('supply', item => item.supply)
    },
    {
      key: 'return_temp',
      label: 'Обратка',
      color: themeColor('--chart-return', '#16a34a'),
      values: valuePoints('return_temp', item => item.return_temp)
    },
    {
      key: 'pump_temp',
      label: 'Насос',
      color: themeColor('--chart-pump', '#9333ea'),
      values: valuePoints('pump_temp', item => item.pump_temp)
    }
  ];
}

function sensorSeries() {
  const keys = new Set();
  for (const item of items) {
    for (const key of Object.keys(item.sensors || {})) {
      if (key.indexOf(currentBus + ':') === 0) keys.add(key);
    }
  }
  for (const meta of stateSensors) {
    if (meta.bus === currentBus && meta.key) keys.add(meta.key);
  }
  const metas = Array.from(keys).map(sensorMeta);
  metas.sort((a, b) => sensorName(a).localeCompare(sensorName(b), 'ru'));
  return metas.map((meta, index) => ({
    key: meta.key,
    label: sensorName(meta),
    color: paletteColor(index),
    values: valuePoints(meta.key, item => item.sensors && item.sensors[meta.key])
  }));
}

function renderAll() {
  const room = roomSeries();
  const pump = pumpSeries();
  const sensors = sensorSeries();
  drawChart(roomCanvas, room);
  drawChart(pumpCanvas, pump);
  drawChart(sensorsCanvas, sensors.filter(item => !hiddenSensors.has(item.key)));
  renderStaticLegend(roomLegend, room);
  renderStaticLegend(pumpLegend, pump);
  renderSensorLegend(sensors);
}

function setRangeButtons() {
  document.querySelectorAll('button[data-range]').forEach(button => {
    button.classList.toggle('secondary', Number(button.dataset.range) !== currentRange);
  });
}

async function load(range) {
  currentRange = range;
  setRangeButtons();
  statusLine.textContent = 'Загрузка…';
  try {
    const [historyResponse, stateResponse] = await Promise.all([
      fetch('api/history.lsp?range=' + range, { cache: 'no-store' }),
      fetch('api/state.lsp', { cache: 'no-store' })
    ]);
    const historyData = await historyResponse.json();
    const stateData = await stateResponse.json();
    items = asArray(historyData.items);
    stateSensors = asArray(stateData.sensors);
    statusLine.textContent = items.length ? '' : 'За выбранный период данных нет.';
    renderAll();
  } catch (error) {
    statusLine.textContent = 'Не удалось загрузить историю.';
  }
}

document.querySelectorAll('button[data-range]').forEach(button => {
  button.addEventListener('click', () => load(Number(button.dataset.range)));
});
busSelect.addEventListener('change', () => {
  currentBus = busSelect.value;
  hiddenSensors.clear();
  renderAll();
});
document.addEventListener('thermostat:theme', renderAll);
load(currentRange);
</script>
</body>
</html>
