#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /etc/os-release ]]; then
    echo 'Automatic dependencies require Ubuntu/Debian. Install dependencies manually, then use make setup SKIP_DEPS=1.' >&2
    exit 1
fi
. /etc/os-release
if [[ "${ID:-}" != ubuntu && "${ID:-}" != debian ]]; then
    echo 'Automatic dependencies require Ubuntu/Debian. Install dependencies manually, then use make setup SKIP_DEPS=1.' >&2
    exit 1
fi

privilege=()
if [[ "$EUID" -ne 0 ]]; then
    privilege=(sudo)
fi
"${privilege[@]}" apt-get update
"${privilege[@]}" apt-get install -y \
    git wget flex bison gperf python3 python3-pip python3-venv \
    cmake ninja-build ccache libffi-dev libssl-dev dfu-util \
    libusb-1.0-0 build-essential
