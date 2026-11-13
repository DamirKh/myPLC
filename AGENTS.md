# AGENTS.md

## Project

Xedge32 thermostat for a hydronic floor-heating pump. Lua application runs on
ESP32-S3 (N16R8). Normative behavior lives in `docs/decisions.md`; wiring and
safety — `docs/hardware.md`; operations — `docs/deployment.md`; debug journal —
`docs/notes.md`.

## Build and test

```bash
make test       # pure Lua 5.4 unit tests
make package    # build/thermostat.zip for Xedge32
```

If `lua5.4` is not installed, use any Lua 5.4 interpreter. Do not add a Lua
package manager dependency.

## Deploy

Upload `build/thermostat.zip` through Xedge32 **Firmware Update & App Upload**;
see `docs/deployment.md`. The ZIP must contain the contents of `thermostat/`,
not the directory itself.

## Code conventions

- Lua 5.4, 3-space indentation, no tabs.
- Pure logic modules must not call `esp32.*` at load time; hardware access is
  isolated in `thermostat/.lua/modules/onewire_rmt.lua` and `.preload`.
- Module dependencies use `require("modules.<name>")`.
- Keep public API functions on the `app` table through globals defined in
  `.preload`.
- Xedge `ba.timer` callbacks stop when they return; repeating logic must be a
  coroutine loop that calls `coroutine.yield(true)` on every iteration.
- The application must run without internet access: no CDNs, external fonts,
  remote scripts, or required cloud calls. Keep all runtime assets on board.
- Use the CSS variables in `static/style.css` for all UI colors so light and dark
  themes stay consistent. New pages must load `/static/theme.js` in `<head>`.
- Do not add comments unless they explain a non-obvious safety invariant.

## Documentation authority

- Normative behavior lives in `docs/decisions.md`. When changing behavior,
  update it there; do not restate the same rules in `README.md`, `AGENTS.md` or
  `docs/notes.md`.
- `docs/notes.md` is a debug journal: problem, cause, fix, verification, and a
  link to the relevant decision.
- Keep safety invariants below in sync with `docs/decisions.md` and
  `docs/hardware.md`.

## Safety invariants

- Pump is OFF at boot until valid room and floor readings exist.
- A floor over-limit and any critical fault turn the pump OFF immediately,
  bypassing minimum on-time.
- Failed sensors are excluded; if no valid room or no valid floor sensor
  remains, the pump is OFF.
- SSR output is active-high by default; the hardware must have a pull-down so
  reset/boot means pump OFF.
- Keep the LED slot timer independent from sensor and control loops. Active slots
  are shown in order red (fault), blue (STA down), purple (AP without a recent
  web client), yellow (service), green (pump, always present); each slot lasts
  1.2 s with a 0.4 s off gap. A frozen slot sequence is the visual hang indicator.
- Never store MQTT passwords or Wi-Fi credentials in git. Wi-Fi credentials are
  device-only; the password must stay encrypted with a softTPM-derived key.
- ESP-NOW uses a single receiver. The callback must only enqueue packets; parsing,
  config writes and control work belong in the application loop.
- Provisioned ESP-NOW nodes are identified by their MAC allowlist. The `PROV`
  token is a matching aid, not authentication.
- ESP-NOW sensor data may influence the pump only after MAC allowlist, XNW1 v2
  length/version checks, per-slot status handling and the ESP-NOW staleness
  timeout. Never treat unauthenticated packets as trusted commands.
- Admin pages and admin mutations stay under `/admin/` behind the 4-digit PIN
  session; public pages must not expose configuration changes.
- Do not weaken the public/protected split without updating `docs/decisions.md`.
