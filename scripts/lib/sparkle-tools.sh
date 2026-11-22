# shellcheck shell=bash
# Sparkle for the macOS app: the framework the app loads at run time and the
# sign_update tool, from the pinned release archive.

MIM_SPARKLE_VERSION="2.10.0"
MIM_SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

# Downloads and verifies the pinned Sparkle release into build/sparkle once;
# prints the directory.
mim_sparkle_fetch() {
  local root dir archive
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  dir="$root/build/sparkle/$MIM_SPARKLE_VERSION"
  if [[ ! -d "$dir/Sparkle.framework" ]]; then
    mkdir -p "$dir"
    archive="$dir/Sparkle-$MIM_SPARKLE_VERSION.tar.xz"
    curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error --output "$archive" \
      "https://github.com/sparkle-project/Sparkle/releases/download/$MIM_SPARKLE_VERSION/Sparkle-$MIM_SPARKLE_VERSION.tar.xz"
    echo "$MIM_SPARKLE_SHA256  $archive" | shasum -a 256 --check --status || {
      echo "Sparkle archive checksum mismatch" >&2
      rm -f "$archive"
      return 1
    }
    tar -xJf "$archive" -C "$dir" ./Sparkle.framework ./bin
    rm -f "$archive"
  fi
  printf '%s\n' "$dir"
}

mim_sparkle_sign_update() {
  local dir
  dir="$(mim_sparkle_fetch)" || return 1
  printf '%s\n' "$dir/bin/sign_update"
}
