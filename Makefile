.DEFAULT_GOAL := help
.DELETE_ON_ERROR:
SHELL := /bin/bash

PLATFORM ?= milkv
ifneq ($(PLATFORM),milkv)
ifneq ($(PLATFORM),qemu)
$(error Unsupported PLATFORM '$(PLATFORM)'; choose milkv or qemu)
endif
endif
BUILD_DIR := build/$(PLATFORM)

CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
SIZE := $(CROSS_COMPILE)size
DTC ?= dtc
MKIMAGE ?= mkimage
PYTHON ?= .venv/bin/python
QEMU ?= qemu-system-riscv64
QEMU_BIOS ?= default
PORT ?= /dev/ttyUSB0
SD_DIR ?=
export CHIBI_PORT := $(PORT)
export CHIBI_SD_DIR := $(SD_DIR)
export CHIBI_SKIP_DEPS := $(SKIP_DEPS)
export CHIBI_PLATFORM := $(PLATFORM)
export CHIBI_QEMU := $(QEMU)
export CHIBI_QEMU_BIOS := $(QEMU_BIOS)

ARCH_FLAGS := -march=rv64imac_zicsr_zifencei -mabi=lp64 -mcmodel=medany -mno-relax
CFLAGS := $(ARCH_FLAGS) -std=c11 -O2 -g -Wall -Wextra -Werror \
          -ffreestanding -fno-builtin -fno-pie -fno-stack-protector \
          -fno-unwind-tables -fno-asynchronous-unwind-tables \
          -msmall-data-limit=0 -Iplatforms/$(PLATFORM) -Iinclude -MMD -MP
LDFLAGS := $(ARCH_FLAGS) -nostdlib -nostartfiles -static \
           -Wl,--build-id=none,--no-relax,-T,kernel.ld,-Map,$(BUILD_DIR)/chibi-os.map
OBJECTS := $(addprefix $(BUILD_DIR)/,start.o kernel.o uart.o)
TOOLS := $(CC) $(OBJCOPY) $(OBJDUMP) $(SIZE)
ifeq ($(PLATFORM),milkv)
TOOLS += $(DTC) $(MKIMAGE)
IMAGE := $(BUILD_DIR)/chibi-os.itb
else
IMAGE := $(BUILD_DIR)/chibi-os.elf
endif

.PHONY: help setup setup-test check-tools build clean clean-all test inspect monitor sd-copy boot-commands qemu run test-qemu qemu-smoke
help:
	@printf '%s\n' \
	  'make setup                         Install compiler, FIT tools and QEMU/OpenSBI (Ubuntu/Debian)' \
	  'make qemu                          Build for QEMU virt and print Hello chibi-os (Ctrl+A, X exits)' \
	  'make build PLATFORM=milkv          Build build/milkv/chibi-os.itb (default platform)' \
	  'make build PLATFORM=qemu           Build build/qemu/chibi-os.elf' \
	  'make run PLATFORM=qemu             Build and run QEMU virt' \
	  'make setup-test                    Install optional Python emulator test dependencies' \
	  'make test PLATFORM=milkv|qemu       Run binary tests; qemu also runs a real QEMU smoke test' \
	  'make test-qemu                     QEMU boot smoke test (no Python packages needed)' \
	  'make sd-copy SD_DIR=/media/user/boot  Copy only the Milk-V FIT to mounted SD' \
	  'make monitor PORT=/dev/ttyUSB0      Open hardware UART (115200 8N1)' \
	  'make boot-commands                 Print Milk-V U-Boot commands' \
	  'make inspect PLATFORM=milkv|qemu    Show disassembly (and FIT metadata for milkv)' \
	  'make clean PLATFORM=milkv|qemu      Remove only that platform build output' \
	  'make clean-all                     Remove all build output, including old flat build/'

setup:
	@bash scripts/setup.sh
	@$(MAKE) --no-print-directory check-tools
	@command -v "$(QEMU)" >/dev/null || { echo 'qemu-system-riscv64 is missing.' >&2; exit 1; }

setup-test:
	python3 -m venv .venv
	.venv/bin/python -m pip install -r requirements-test.txt

check-tools:
	@for tool in $(TOOLS); do \
	  command -v "$$tool" >/dev/null || { printf 'Missing %s: run make setup.\n' "$$tool" >&2; exit 1; }; \
	done

build: $(IMAGE) $(BUILD_DIR)/chibi-os.bin
	@$(SIZE) $(BUILD_DIR)/chibi-os.elf

$(BUILD_DIR)/start.o: src/start.S Makefile | build-dir check-tools
	$(CC) $(CFLAGS) -c $< -o $@
$(BUILD_DIR)/%.o: src/%.c Makefile | build-dir check-tools
	$(CC) $(CFLAGS) -c $< -o $@
$(BUILD_DIR)/chibi-os.elf: $(OBJECTS) kernel.ld
	$(CC) $(LDFLAGS) $(OBJECTS) -o $@
$(BUILD_DIR)/chibi-os.bin: $(BUILD_DIR)/chibi-os.elf
	$(OBJCOPY) -O binary $< $@

# FIT is only a Milk-V artifact. QEMU uses its generated DTB and the ELF.
ifeq ($(PLATFORM),milkv)
$(BUILD_DIR)/duo.dtb: boot/duo.dts | build-dir check-tools
	$(DTC) -I dts -O dtb -o $@ $<
$(BUILD_DIR)/chibi-os.its: boot/chibi-os.its | build-dir
	cp $< $@
$(BUILD_DIR)/chibi-os.itb: $(BUILD_DIR)/chibi-os.bin $(BUILD_DIR)/duo.dtb $(BUILD_DIR)/chibi-os.its
	cd $(BUILD_DIR) && $(MKIMAGE) -f chibi-os.its chibi-os.itb
endif

.PHONY: build-dir
build-dir:
	@mkdir -p $(BUILD_DIR)

inspect: build
	$(OBJDUMP) -d $(BUILD_DIR)/chibi-os.elf
ifeq ($(PLATFORM),milkv)
	$(MKIMAGE) -l $(BUILD_DIR)/chibi-os.itb
endif

test: build
	@test -x "$(PYTHON)" || { echo 'Run make setup-test first, or set PYTHON=/path/to/python.' >&2; exit 1; }
	$(PYTHON) tests/test_boot.py
ifeq ($(PLATFORM),qemu)
	python3 tests/test_qemu.py
endif

# Always select qemu explicitly, even when the outer make defaults to milkv.
qemu:
	@$(MAKE) --no-print-directory PLATFORM=qemu run

test-qemu:
	@$(MAKE) --no-print-directory PLATFORM=qemu qemu-smoke

ifeq ($(PLATFORM),qemu)
run: build
	@bash scripts/qemu.sh
qemu-smoke: build
	python3 tests/test_qemu.py
sd-copy monitor boot-commands:
	@echo '$@ is Milk-V-only; use PLATFORM=milkv.' >&2; exit 1
else
run qemu-smoke:
	@echo 'Use make qemu or PLATFORM=qemu.' >&2; exit 1
sd-copy: build
	@python3 scripts/sd_copy.py
monitor:
	@test -n "$$CHIBI_PORT" || { echo 'PORT is required.' >&2; exit 1; }
	@command -v picocom >/dev/null || { echo 'Install picocom with make setup.' >&2; exit 1; }
	picocom --baud 115200 --databits 8 --parity n --stopbits 1 --flow n "$$CHIBI_PORT"
boot-commands:
	@cat boot/commands.txt
endif

clean:
	rm -rf $(BUILD_DIR)
clean-all:
	rm -rf build

-include $(OBJECTS:.o=.d)
