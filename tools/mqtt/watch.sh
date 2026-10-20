#!/bin/sh
set -eu

NAME=${MQTT_CONTAINER:-myplc-mqtt}
TOPIC=${MQTT_TOPIC:-home/floor/thermostat/#}

if ! docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -qx true; then
   echo "Broker $NAME is not running. Run: make mqtt-up" >&2
   exit 1
fi

exec docker exec "$NAME" mosquitto_sub -h 127.0.0.1 -v -t "$TOPIC"
