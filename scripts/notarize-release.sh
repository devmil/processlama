#!/usr/bin/env bash
# Notarize and staple the release DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIM_REPO_ROOT="$ROOT"

# shellcheck source=lib/load-signing-env.sh
source "$ROOT/scripts/lib/load-signing-env.sh"

DMG="${1:-$ROOT/build/archive/ProcessLama.dmg}"
[[ -f "$DMG" ]] || {
  echo "notarize-release.sh: DMG not found: $DMG" >&2
  exit 1
}

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "${APPLE_API_KEY_FILE:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
  xcrun notarytool submit "$DMG" \
    --key "$APPLE_API_KEY_FILE" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" \
    --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${TEAM_ID:-}" ]]; then
  xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait
else
  echo "notarize-release.sh: configure a notary profile, API key, or Apple ID credentials." >&2
  exit 1
fi

stapled=0
for attempt in 1 2 3 4 5; do
  if xcrun stapler staple "$DMG"; then
    stapled=1
    break
  fi
  [[ "$attempt" -lt 5 ]] || break
  delay=$(( attempt * ${PROCESSLAMA_STAPLE_RETRY_SECONDS:-30} ))
  echo "notarize-release: stapling attempt $attempt failed; retrying in ${delay}s" >&2
  sleep "$delay"
done
[[ "$stapled" -eq 1 ]] || { echo 'notarize-release: stapling failed after five attempts' >&2; exit 1; }
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true
echo "==> Notarized and stapled $DMG" >&2
