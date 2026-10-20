#!/bin/sh
set -eu

NAME=${MQTT_CONTAINER:-myplc-mqtt}

if ! docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -qx true; then
   echo "Broker $NAME is not running. Run: make mqtt-up" >&2
   exit 1
fi

docker exec "$NAME" mosquitto_pub -h 127.0.0.1 -t myplc/test -m local-broker-ok -r
VALUE=$(docker exec "$NAME" mosquitto_sub -h 127.0.0.1 -t myplc/test -C 1 -W 5)
docker exec "$NAME" mosquitto_pub -h 127.0.0.1 -t myplc/test -n -r

if [ "$VALUE" != "local-broker-ok" ]; then
   echo "MQTT broker test failed: got '$VALUE'" >&2
   exit 1
fi

echo "MQTT broker test passed"
