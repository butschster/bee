WIPPY ?= .wippy/bin/wippy
.PHONY: setup run lint test pack check
setup:
	python3 scripts/runtime_setup.py
run:
	BEE_RUNTIME="$(abspath $(WIPPY))" bash ./run.sh
lint:
	$(WIPPY) lint
test:
	BEE_RUNTIME="$(abspath $(WIPPY))" python3 tests/unit.py
pack:
	mkdir -p dist
	$(WIPPY) pack dist/bee.wapp

check: lint test pack
	BEE_RUNTIME="$(abspath $(WIPPY))" python3 tests/architecture.py
	BEE_RUNTIME="$(abspath $(WIPPY))" python3 tests/storage.py
	BEE_RUNTIME="$(abspath $(WIPPY))" python3 tests/tui_smoke.py
	BEE_RUNTIME="$(abspath $(WIPPY))" python3 tests/console.py
	BEE_RUNTIME="$(abspath $(WIPPY))" python3 tests/lifecycle.py
	BEE_RUNTIME="$(abspath $(WIPPY))" python3 tests/recovery.py
