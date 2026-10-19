LUA ?= lua5.4

.PHONY: test package clean

test:
	$(LUA) tests/run.lua

package:
	rm -rf build
	mkdir -p build
	cd thermostat && zip -D -q -u -r -9 ../build/thermostat.zip . \
		-x 'config.json' 'history.jsonl' 'userdb.encrypted'
	@echo "built build/thermostat.zip"

clean:
	rm -rf build
