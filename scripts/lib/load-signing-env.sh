# shellcheck shell=bash
# Source optional release signing environment from repo root.

_mim_signing_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -f "$_mim_signing_root/.env.signing" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$_mim_signing_root/.env.signing"
  set +a
fi
unset _mim_signing_root
