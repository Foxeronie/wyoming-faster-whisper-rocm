#!/usr/bin/env bash
set -euo pipefail

MODEL="${WYOMING_MODEL:-distil-small.en}"
URI="${WYOMING_URI:-tcp://0.0.0.0:10300}"
DEVICE="${WYOMING_DEVICE:-cuda}"
COMPUTE_TYPE="${WYOMING_COMPUTE_TYPE:-default}"
BEAM_SIZE="${WYOMING_BEAM_SIZE:-5}"
LANGUAGE="${WYOMING_LANGUAGE:-}"
INITIAL_PROMPT="${WYOMING_INITIAL_PROMPT:-}"
EXTRA_ARGS="${WYOMING_EXTRA_ARGS:-}"

DATA_DIRS_RAW="${WYOMING_DATA_DIRS:-/data}"
IFS=':' read -r -a DATA_DIRS <<< "${DATA_DIRS_RAW}"

if [ "${#DATA_DIRS[@]}" -eq 0 ] || [ -z "${DATA_DIRS[0]}" ]; then
  echo "At least one data directory must be provided via WYOMING_DATA_DIRS or /data volume." >&2
  exit 1
fi

DOWNLOAD_DIR="${WYOMING_DOWNLOAD_DIR:-${DATA_DIRS[0]}}"

ARGS=(
  "--device" "${DEVICE}"
  "--model" "${MODEL}"
  "--uri" "${URI}"
  "--compute-type" "${COMPUTE_TYPE}"
  "--beam-size" "${BEAM_SIZE}"
  "--download-dir" "${DOWNLOAD_DIR}"
)

for dir in "${DATA_DIRS[@]}"; do
  ARGS+=("--data-dir" "${dir}")
done

if [ -n "${LANGUAGE}" ]; then
  ARGS+=("--language" "${LANGUAGE}")
fi

if [ -n "${INITIAL_PROMPT}" ]; then
  ARGS+=("--initial-prompt" "${INITIAL_PROMPT}")
fi

case "${WYOMING_DEBUG:-}" in
  1 | true | yes) ARGS+=("--debug") ;;
esac

if [ -n "${EXTRA_ARGS}" ]; then
  # shellcheck disable=SC2206
  EXTRA_SPLIT=( ${EXTRA_ARGS} )
  ARGS+=("${EXTRA_SPLIT[@]}")
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"

exec "${PYTHON_BIN}" -m wyoming_whisper "${ARGS[@]}" "$@"
