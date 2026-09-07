#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
bee_runtime="${BEE_RUNTIME:-$PWD/.wippy/bin/wippy}"
if [[ ! -x "$bee_runtime" ]]; then
  echo 'Set BEE_RUNTIME to a Wippy binary with viewport mounts and page support (#653).' >&2
  exit 1
fi
exec "$bee_runtime" run bee "$@"
