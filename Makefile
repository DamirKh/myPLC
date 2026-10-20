LUA ?= lua5.4
MQTT_CONTAINER ?= myplc-mqtt

.PHONY: test package clean mqtt-up mqtt-down mqtt-logs mqtt-test mqtt-watch

test:
	$(LUA) tests/run.lua

mqtt-up:
	MQTT_CONTAINER=$(MQTT_CONTAINER) tools/mqtt/up.sh

mqtt-down:
	-@docker stop $(MQTT_CONTAINER) >/dev/null 2>&1 || true

mqtt-logs:
	docker logs -f $(MQTT_CONTAINER)

mqtt-test:
	MQTT_CONTAINER=$(MQTT_CONTAINER) tools/mqtt/test.sh

mqtt-watch:
	MQTT_CONTAINER=$(MQTT_CONTAINER) tools/mqtt/watch.sh

package:
	rm -rf build
	mkdir -p build
	cd thermostat && zip -D -q -u -r -9 ../build/thermostat.zip . \
		-x 'config.json' 'history.jsonl' 'userdb.encrypted'
	@echo "built build/thermostat.zip"

clean:
	rm -rf build
