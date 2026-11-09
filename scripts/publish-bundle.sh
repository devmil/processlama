#!/usr/bin/env bash
# Build and publish one platform's bundles for an existing release tag.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIM_REPO_ROOT="$ROOT"
# shellcheck source=lib/version.sh
source "$ROOT/scripts/lib/version.sh"
# shellcheck source=lib/release-channel.sh
source "$ROOT/scripts/lib/release-channel.sh"
# shellcheck source=lib/release-git.sh
source "$ROOT/scripts/lib/release-git.sh"
# shellcheck source=lib/website-release.sh
source "$ROOT/scripts/lib/website-release.sh"
# shellcheck source=lib/sparkle-appcast.sh
source "$ROOT/scripts/lib/sparkle-appcast.sh"
# shellcheck source=lib/sparkle-tools.sh
source "$ROOT/scripts/lib/sparkle-tools.sh"

MIM_TAG=""
MIM_PLATFORM=""
MIM_FORMATS="appimage,rpm,deb,tar"
MIM_SKIP_SIGN=0
MIM_SKIP_NOTARIZE=0
MIM_ALLOW_UNSIGNED_APPCAST=0
MIM_GIT_COMMIT=1

usage() {
  cat <<'EOF'
Usage: ./scripts/publish-bundle.sh --tag TAG --platform linux|macos [options]

Builds from an existing immutable release tag, copies the platform artifacts to
the website, updates metadata, and creates a separate bundle publication commit.
Sequential publication commits may be made from the tag or prior website-only
publication commits for the same tag.

Options:
  --formats appimage,rpm,deb,tar  Linux formats (default: all)
  --skip-sign                    Build an unsigned macOS app
  --skip-notarize                Skip Apple notarization
  --allow-unsigned-appcast       Local macOS rehearsal only
  --no-git-commit                Leave website changes uncommitted
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) shift; MIM_TAG="${1:?--tag requires a value}" ;;
    --platform) shift; MIM_PLATFORM="${1:?--platform requires linux|macos}" ;;
    --formats) shift; MIM_FORMATS="${1:?--formats requires a list}" ;;
    --skip-sign) MIM_SKIP_SIGN=1 ;;
    --skip-notarize) MIM_SKIP_NOTARIZE=1 ;;
    --allow-unsigned-appcast) MIM_ALLOW_UNSIGNED_APPCAST=1 ;;
    --no-git-commit) MIM_GIT_COMMIT=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "publish-bundle.sh: unknown option $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

[[ -n "$MIM_TAG" ]] || { echo "publish-bundle.sh: --tag is required" >&2; exit 64; }
case "$MIM_PLATFORM" in linux|macos) ;; *) echo "publish-bundle.sh: --platform linux|macos is required" >&2; exit 64 ;; esac
cd "$ROOT"
mim_read_version
expected_tag="$(mim_release_tag_name)"
[[ "$MIM_TAG" == "$expected_tag" ]] || {
  echo "publish-bundle.sh: VERSION expects tag $expected_tag, not $MIM_TAG" >&2
  exit 1
}
mim_require_release_tag_checkout "$MIM_TAG"
if mim_is_prerelease_version "$MIM_MARKETING_VERSION"; then
  MIM_RELEASE_CHANNEL=beta
else
  MIM_RELEASE_CHANNEL=stable
fi
export MIM_RELEASE_CHANNEL

declare -a committed_paths=("website/download/$(mim_release_notes_html_filename)")
if [[ "$MIM_PLATFORM" == "linux" ]]; then
  [[ "$(uname -s)" == "Linux" ]] || { echo "publish-bundle.sh: Linux bundles must be built on Linux" >&2; exit 1; }
  ./scripts/package-linux.sh --formats "$MIM_FORMATS"
  machine_arch="$(uname -m)"
  [[ "$machine_arch" == "arm64" ]] && machine_arch="aarch64"
  IFS=',' read -r -a formats <<<"$MIM_FORMATS"
  for format in "${formats[@]}"; do
    filename="$(mim_linux_artifact_filename "$format" "$machine_arch")"
    mim_publish_artifact_to_website "$ROOT/build/archive/$filename" linux "$format" "$machine_arch" "Linux"
    committed_paths+=("website/download/$filename")
  done
else
  [[ "$(uname -s)" == "Darwin" ]] || { echo "publish-bundle.sh: macOS bundles must be built on macOS" >&2; exit 1; }
  if [[ "$MIM_SKIP_SIGN" -eq 1 ]]; then
    ./scripts/package-release.sh --skip-sign
  else
    ./scripts/package-release.sh
  fi
  dmg="$ROOT/build/archive/ProcessLama.dmg"
  if [[ "$MIM_SKIP_NOTARIZE" -eq 0 ]]; then
    ./scripts/notarize-release.sh "$dmg"
  fi
  published_name="$(mim_dmg_filename)"
  versioned_dmg="$ROOT/build/archive/$published_name"
  cp "$dmg" "$versioned_dmg"
  sparkle_signature=""
  if [[ "$MIM_ALLOW_UNSIGNED_APPCAST" -eq 0 ]]; then
    sign_update="$(mim_sparkle_sign_update)"
    sparkle_signature="$("$sign_update" -p "$versioned_dmg")"
  fi
  mim_publish_artifact_to_website "$versioned_dmg" macos dmg \
    "Apple Silicon & Intel" "macOS 14.0" "" "$sparkle_signature"
  mim_generate_sparkle_appcast $((1 - MIM_ALLOW_UNSIGNED_APPCAST))
  committed_paths+=("website/download/$published_name")
fi

[[ "$MIM_GIT_COMMIT" -eq 0 ]] || mim_commit_bundle_artifacts "$MIM_PLATFORM" "${committed_paths[@]}"
echo "==> $MIM_PLATFORM bundles for $MIM_TAG are ready. Push the publication commit to main after review." >&2
