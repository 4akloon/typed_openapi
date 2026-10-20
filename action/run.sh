#!/usr/bin/env bash
# Runs typed_openapi with the inputs of the action (INPUT_* variables). The
# arguments live in an array: no input is ever part of a command line string.
set -euo pipefail

command=${INPUT_COMMAND:-lint}
args=("$command" --format "${INPUT_FORMAT:-github-actions}")

case "$command" in
  lint)
    if [ -z "${INPUT_SPEC:-}" ]; then
      echo "::error::The lint command needs the 'spec' input."
      exit 64
    fi
    [ -z "${INPUT_PRESET:-}" ] || args+=(--preset "$INPUT_PRESET")
    [ -z "${INPUT_FAIL_ON:-}" ] || args+=(--fail-on "$INPUT_FAIL_ON")
    args+=("$INPUT_SPEC")
    ;;
  check)
    if [ -n "${INPUT_SPEC:-}" ] || [ -n "${INPUT_PRESET:-}" ] || [ -n "${INPUT_FAIL_ON:-}" ]; then
      echo "::error::The check command reads a config: the 'spec', 'preset' and 'fail-on' inputs are for lint."
      exit 64
    fi
    args+=(--config "${INPUT_CONFIG:-typed_openapi.yaml}")
    ;;
  *)
    echo "::error::The 'command' input is 'lint' or 'check', not '$command'."
    exit 64
    ;;
esac

exec "$INPUT_EXECUTABLE" "${args[@]}"
