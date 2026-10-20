<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>История — тёплый пол</title>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="static/style.css?v=4">
</head>
<body>
<main>
<header>
  <div><h1>История</h1><p class="muted">Температуры за выбранный период</p></div>
  <nav><a href="/">Обзор</a><a href="/admin/settings.lsp">Настройки</a><a href="/admin/sensors.lsp">Датчики</a></nav>
</header>

<section class="card">
  <div class="row">
    <button data-range="3600">1 час</button>
    <button data-range="86400">24 часа</button>
    <button data-range="604800">7 дней</button>
  </div>
  <canvas id="chart" width="1000" height="360"></canvas>
  <p class="muted">Линии: комната, пол, подача.</p>
</section>
</main>
<script>
const canvas = document.getElementById('chart');
const ctx = canvas.getContext('2d');
const asArray = v => Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []);
let currentRange = 86400;

function lineColor(name) {
  return {room: '#2563eb', floor: '#f59e0b', supply: '#dc2626'}[name] || '#666';
}

function draw(items) {
  const w = canvas.width, h = canvas.height;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = '#d7dee8';
  ctx.lineWidth = 1;
  for (let i = 0; i <= 4; i++) {
    const y = 20 + i * (h - 40) / 4;
    ctx.beginPath(); ctx.moveTo(54, y); ctx.lineTo(w - 12, y); ctx.stroke();
  }
  if (!Array.isArray(items) || items.length < 2) {
    ctx.fillStyle = '#5b667a';
    ctx.fillText('Нет данных', 20, 30);
    return;
  }
  const times = items.map(x => x.t);
  const t0 = Math.min(...times), t1 = Math.max(...times);
  const values = [];
  for (const x of items) {
    for (const k of ['room', 'floor', 'supply']) {
      if (typeof x[k] === 'number') values.push(x[k]);
    }
  }
  if (!values.length) return;
  let v0 = Math.min(...values), v1 = Math.max(...values);
  const pad = Math.max(1, (v1 - v0) * 0.15);
  v0 -= pad; v1 += pad;
  const xOf = t => 54 + (t - t0) / Math.max(1, t1 - t0) * (w - 66);
  const yOf = v => 20 + (v1 - v) / Math.max(0.1, v1 - v0) * (h - 40);
  ctx.fillStyle = '#5b667a';
  ctx.font = '12px sans-serif';
  for (let i = 0; i <= 4; i++) {
    const v = v1 - i * (v1 - v0) / 4;
    ctx.fillText(v.toFixed(1) + '°', 6, 24 + i * (h - 40) / 4);
  }
  for (const key of ['room', 'floor', 'supply']) {
    ctx.strokeStyle = lineColor(key);
    ctx.lineWidth = 2;
    ctx.beginPath();
    let started = false;
    for (const x of items) {
      if (typeof x[key] !== 'number') { started = false; continue; }
      const px = xOf(x.t), py = yOf(x[key]);
      if (!started) { ctx.moveTo(px, py); started = true; }
      else ctx.lineTo(px, py);
    }
    ctx.stroke();
  }
}

async function load(range) {
  currentRange = range;
  const r = await fetch('api/history.lsp?range=' + range, {cache: 'no-store'});
  const data = await r.json();
  draw(asArray(data.items));
}

document.querySelectorAll('button[data-range]').forEach(b => {
  b.addEventListener('click', () => load(Number(b.dataset.range)));
});
load(currentRange);
</script>
</body>
</html>
