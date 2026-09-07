.DEFAULT_GOAL := help
.DELETE_ON_ERROR:
SHELL := /bin/bash

CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
SIZE := $(CROSS_COMPILE)size
DTC ?= dtc
MKIMAGE ?= mkimage
PYTHON ?= .venv/bin/python
PORT ?= /dev/ttyUSB0
SD_DIR ?=
export CHIBI_PORT := $(PORT)
export CHIBI_SD_DIR := $(SD_DIR)
export CHIBI_SKIP_DEPS := $(SKIP_DEPS)

ARCH_FLAGS := -march=rv64imac_zicsr_zifencei -mabi=lp64 -mcmodel=medany -mno-relax
CFLAGS := $(ARCH_FLAGS) -std=c11 -O2 -g -Wall -Wextra -Werror \
          -ffreestanding -fno-builtin -fno-pie -fno-stack-protector \
          -fno-unwind-tables -fno-asynchronous-unwind-tables \
          -msmall-data-limit=0 -Iinclude -MMD -MP
LDFLAGS := $(ARCH_FLAGS) -nostdlib -nostartfiles -static \
           -Wl,--build-id=none,--no-relax,-T,kernel.ld,-Map,build/chibi-os.map
OBJECTS := build/start.o build/kernel.o build/uart.o

.PHONY: help setup setup-test check-tools build clean test inspect monitor sd-copy boot-commands
help:
	@printf '%s\n' \
	  'make setup                      Ubuntu/Debian: install cross compiler and FIT tools' \
	  'make build                      Create build/chibi-os.itb for Milk-V Duo (64MB)' \
	  'make setup-test                 Install optional Python emulator test dependencies' \
	  'make test                       Build and test the actual RV64 binary with mocked UART' \
	  'make sd-copy SD_DIR=/media/user/boot  Copy only chibi-os.itb to a mounted FAT partition' \
	  'make monitor PORT=/dev/ttyUSB0   Open UART console (115200 8N1)' \
	  'make boot-commands              Print commands to enter at the U-Boot prompt' \
	  'make inspect                    Show ELF disassembly and FIT metadata' \
	  'make clean                      Remove build output'

setup:
	@bash scripts/setup.sh
	@$(MAKE) --no-print-directory check-tools

setup-test:
	python3 -m venv .venv
	.venv/bin/python -m pip install -r requirements-test.txt

check-tools:
	@for tool in "$(CC)" "$(OBJCOPY)" "$(OBJDUMP)" "$(SIZE)" "$(DTC)" "$(MKIMAGE)"; do \
	  command -v "$$tool" >/dev/null || { printf 'Missing %s: run make setup.\n' "$$tool" >&2; exit 1; }; \
	done

build: build/chibi-os.itb
	@$(SIZE) build/chibi-os.elf

build/start.o: src/start.S | build-dir check-tools
	$(CC) $(CFLAGS) -c $< -o $@
build/%.o: src/%.c | build-dir check-tools
	$(CC) $(CFLAGS) -c $< -o $@
build/chibi-os.elf: $(OBJECTS) kernel.ld
	$(CC) $(LDFLAGS) $(OBJECTS) -o $@
build/chibi-os.bin: build/chibi-os.elf
	$(OBJCOPY) -O binary $< $@
build/duo.dtb: boot/duo.dts | build-dir check-tools
	$(DTC) -I dts -O dtb -o $@ $<
build/chibi-os.its: boot/chibi-os.its | build-dir
	cp $< $@
build/chibi-os.itb: build/chibi-os.bin build/duo.dtb build/chibi-os.its
	cd build && $(MKIMAGE) -f chibi-os.its chibi-os.itb

.PHONY: build-dir
build-dir:
	@mkdir -p build

inspect: build
	$(OBJDUMP) -d build/chibi-os.elf
	$(MKIMAGE) -l build/chibi-os.itb

test: build
	@test -x "$(PYTHON)" || { echo 'Run make setup-test first, or set PYTHON=/path/to/python.' >&2; exit 1; }
	$(PYTHON) tests/test_boot.py

sd-copy: build
	@python3 scripts/sd_copy.py

monitor:
	@test -n "$$CHIBI_PORT" || { echo 'PORT is required.' >&2; exit 1; }
	@command -v picocom >/dev/null || { echo 'Install picocom with make setup.' >&2; exit 1; }
	picocom --baud 115200 --databits 8 --parity n --stopbits 1 --flow n "$$CHIBI_PORT"

boot-commands:
	@cat boot/commands.txt

clean:
	rm -rf build

-include $(OBJECTS:.o=.d)
