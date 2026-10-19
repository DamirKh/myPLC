#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$root/build"
mkdir -p "$root/build"
cd "$root/thermostat"
zip -D -q -u -r -9 "$root/build/thermostat.zip" . \
  -x 'config.json' 'history.jsonl' 'userdb.encrypted'
echo "built $root/build/thermostat.zip"
