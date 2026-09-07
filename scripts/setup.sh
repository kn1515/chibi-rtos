#!/usr/bin/env bash
set -eo pipefail

idf_dir="${CHIBI_IDF_DIR:?IDF_DIR is required}"
idf_version=v5.5.1
if [[ "$idf_dir" != /* || "$idf_dir" == *[[:space:]]* ]]; then
    echo 'IDF_DIR must be an absolute path without whitespace.' >&2
    exit 1
fi

if [[ "${CHIBI_SKIP_DEPS:-0}" != 1 ]]; then
    bash scripts/deps.sh
fi

if [[ ! -e "$idf_dir" ]]; then
    mkdir -p "$(dirname "$idf_dir")"
    git clone --branch "$idf_version" --recursive \
        https://github.com/espressif/esp-idf.git "$idf_dir"
fi

if [[ ! -d "$idf_dir/.git" || ! -f "$idf_dir/install.sh" ]]; then
    echo "Existing IDF_DIR is not an ESP-IDF checkout: $idf_dir" >&2
    exit 1
fi
expected=$(git -C "$idf_dir" rev-parse --verify "$idf_version^{commit}")
actual=$(git -C "$idf_dir" rev-parse --verify HEAD)
if [[ "$actual" != "$expected" ]]; then
    echo "IDF_DIR must be at $idf_version. Choose another IDF_DIR; existing checkout was not changed." >&2
    exit 1
fi
if [[ -n "$(git -C "$idf_dir" status --porcelain --untracked-files=no)" ]]; then
    echo 'IDF_DIR has tracked changes. Use a clean SDK checkout or another IDF_DIR.' >&2
    exit 1
fi

(
    cd "$idf_dir"
    bash ./install.sh esp32
)
echo 'Setup complete. Run make build; no manual export.sh step is needed.'
