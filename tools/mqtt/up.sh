#!/bin/sh
set -eu

NAME=${MQTT_CONTAINER:-myplc-mqtt}
PORT=${MQTT_PORT:-1883}
BIND=${MQTT_BIND:-0.0.0.0}
IMAGE=${MQTT_IMAGE:-eclipse-mosquitto:2.0}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
   echo "MQTT broker already running: $NAME"
   exit 0
fi

docker run -d --rm --name "$NAME" \
   -p "$BIND:$PORT:1883" \
   -v "$ROOT/tools/mqtt/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro" \
   "$IMAGE" >/dev/null

echo "MQTT broker started: $BIND:$PORT (container $NAME)"
echo "Use this machine's LAN IP as MQTT host in /admin/settings.lsp"
