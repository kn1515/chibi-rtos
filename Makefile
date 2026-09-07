.DEFAULT_GOAL := help
SHELL := /bin/bash

IDF_DIR ?= $(HOME)/esp/esp-idf-v5.5.1
PORT ?=
SKIP_DEPS ?= 0
export CHIBI_IDF_DIR := $(IDF_DIR)
export CHIBI_PORT := $(PORT)
export CHIBI_SKIP_DEPS := $(SKIP_DEPS)

.PHONY: help deps setup build flash monitor flash-monitor menuconfig clean fullclean test

help:
	@printf '%s\n' \
	  'make setup                   Install Ubuntu dependencies and ESP-IDF v5.5.1' \
	  'make setup SKIP_DEPS=1       Install ESP-IDF only (dependencies already installed)' \
	  'make build                   Build firmware for ESP32' \
	  'make flash PORT=/dev/ttyUSB0  Build and flash firmware' \
	  'make monitor PORT=/dev/ttyUSB0' \
	  'make flash-monitor PORT=/dev/ttyUSB0' \
	  'make menuconfig              Open configuration' \
	  'make clean / make fullclean  Clean ESP-IDF build output' \
	  'make test                    Run host tests (no ESP-IDF needed)' \
	  'Override SDK path with IDF_DIR=/absolute/path on each command.'

deps:
	@bash scripts/deps.sh

setup:
	@bash scripts/setup.sh

build menuconfig clean fullclean:
	@bash scripts/idf.sh "$@"

flash monitor:
	@bash scripts/idf.sh "$@"

flash-monitor:
	@bash scripts/idf.sh flash monitor

test:
	@mkdir -p .host-build
	$(CC) -std=c11 -Wall -Wextra -Werror -pedantic -I main main/mini_os.c tests/test_mini_os.c -o .host-build/test_mini_os
	@.host-build/test_mini_os
	@python3 tests/test_make.py
