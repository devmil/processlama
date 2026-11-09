#!/usr/bin/env bash
set -euo pipefail

[[ -x /usr/bin/podman && -x /usr/bin/crun ]] || {
  echo "The workflow-installed Podman/crun pair is unavailable" >&2
  exit 1
}

# The hosted runner uses a job-local rootful container engine.
exec sudo /usr/bin/podman --runtime /usr/bin/crun "$@"
