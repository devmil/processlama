#!/usr/bin/env bash
# Sourced by the release preflight. Requires OpenSSL 3 and a disposable directory.
processlama_validate_release_secrets() {
  local directory="$1" openssl_bin="$2"
  processlama_secret_require MACOS_DEVELOPER_ID_P12_PASSWORD MACOS_CODESIGN_IDENTITY \
    APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID || return 1
  processlama_secret_file SPARKLE_PRIVATE_KEY_BASE64 "$directory/sparkle-ed25519.pem" || return 1
  processlama_secret_file MACOS_DEVELOPER_ID_P12_BASE64 "$directory/developer-id.p12" || return 1
  processlama_secret_file APPLE_NOTARY_KEY_BASE64 "$directory/notary-api-key.p8" || return 1
  python3 - "$directory" <<'PY' || return 1
import base64, pathlib, sys
root = pathlib.Path(sys.argv[1])
try:
    seed = base64.b64decode(b''.join((root / 'sparkle-ed25519.pem').read_bytes().split()), validate=True)
    if len(seed) != 32:
        raise ValueError()
except ValueError:
    raise SystemExit('release-secrets: Sparkle key must be an exported 32-byte seed')
(root / 'sparkle-private.der').write_bytes(bytes.fromhex('302e020100300506032b657004220420') + seed)
PY
  "$openssl_bin" pkey -inform DER -in "$directory/sparkle-private.der" \
    -pubout -outform DER -out "$directory/sparkle-public.der" >/dev/null 2>&1 || return 1
  python3 - "$directory/sparkle-public.der" <<'PY' || return 1
import base64, pathlib, plistlib, sys
actual = base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()[-32:]).decode()
expected = plistlib.loads(pathlib.Path('macos/Runner/Info.plist').read_bytes())['SUPublicEDKey']
if actual != expected:
    raise SystemExit("release-secrets: Sparkle key does not match the app's public key")
PY
  "$openssl_bin" pkcs12 -in "$directory/developer-id.p12" \
    -passin env:MACOS_DEVELOPER_ID_P12_PASSWORD -noout >/dev/null 2>&1 \
    || "$openssl_bin" pkcs12 -legacy -in "$directory/developer-id.p12" \
      -passin env:MACOS_DEVELOPER_ID_P12_PASSWORD -noout >/dev/null 2>&1 || {
    echo 'release-secrets: certificate cannot be opened' >&2; return 1;
  }
  "$openssl_bin" pkey -in "$directory/notary-api-key.p8" -noout >/dev/null 2>&1 || {
    echo 'release-secrets: invalid notarization private key' >&2; return 1;
  }
}
