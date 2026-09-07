#!/usr/bin/env bash
set -eo pipefail

idf_dir="${CHIBI_IDF_DIR:?IDF_DIR is required}"
if [[ "$idf_dir" != /* || "$idf_dir" == *[[:space:]]* ]]; then
    echo 'IDF_DIR must be an absolute path without whitespace.' >&2
    exit 1
fi
if [[ ! -f "$idf_dir/export.sh" ]]; then
    echo 'ESP-IDF is missing. Run make setup first (using the same IDF_DIR).' >&2
    exit 1
fi

serial=0
for action in "$@"; do
    case "$action" in
        flash|monitor) serial=1 ;;
    esac
done
port_args=()
if [[ "$serial" == 1 ]]; then
    if [[ -z "${CHIBI_PORT:-}" ]]; then
        echo 'Specify a serial port: make flash-monitor PORT=/dev/ttyUSB0' >&2
        exit 1
    fi
    port_args=(-p "$CHIBI_PORT")
fi

# ESP-IDF's export script must be sourced in the shell that runs idf.py.
# Do not enable nounset here: the upstream script may read unset variables.
unset IDF_PATH
. "$idf_dir/export.sh"
export IDF_TARGET=esp32
idf.py "${port_args[@]}" "$@"
