# shellcheck shell=bash
# Canonical ProcessLama version helpers.

mim_repo_root() {
  echo "${MIM_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
}

mim_version_file() {
  echo "$(mim_repo_root)/VERSION"
}

mim_read_version() {
  local vf
  vf="$(mim_version_file)"
  [[ -f "$vf" ]] || {
    echo "version: missing $vf" >&2
    return 1
  }
  MIM_MARKETING_VERSION="$(sed -n '1p' "$vf" | tr -d '[:space:]')"
  MIM_BUILD_NUMBER="$(sed -n '2p' "$vf" | tr -d '[:space:]')"
  [[ -n "$MIM_MARKETING_VERSION" && -n "$MIM_BUILD_NUMBER" ]] || {
    echo "version: $vf must contain marketing version and build number on two lines" >&2
    return 1
  }
  export MIM_MARKETING_VERSION MIM_BUILD_NUMBER
}

mim_write_version() {
  printf '%s\n%s\n' "$1" "$2" >"$(mim_version_file)"
  MIM_MARKETING_VERSION="$1"
  MIM_BUILD_NUMBER="$2"
  export MIM_MARKETING_VERSION MIM_BUILD_NUMBER
}

mim_validate_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?(\+[0-9A-Za-z.]+)?$ ]] || {
    echo "version: invalid semver '$1' (expected MAJOR.MINOR.PATCH)" >&2
    return 1
  }
}

mim_validate_build_number() {
  [[ "$1" =~ ^[0-9]+$ && "$1" -gt 0 ]] || {
    echo "version: build number must be a positive integer (got '$1')" >&2
    return 1
  }
}

mim_bump_version() {
  local kind="${1:-build}"
  mim_read_version
  local major minor patch
  IFS='.' read -r major minor patch <<<"${MIM_MARKETING_VERSION%%-*}"
  patch="${patch%%+*}"

  case "$kind" in
    build)
      MIM_BUILD_NUMBER=$((MIM_BUILD_NUMBER + 1))
      ;;
    patch)
      patch=$((patch + 1))
      MIM_MARKETING_VERSION="${major}.${minor}.${patch}"
      MIM_BUILD_NUMBER=$((MIM_BUILD_NUMBER + 1))
      ;;
    minor)
      minor=$((minor + 1))
      MIM_MARKETING_VERSION="${major}.${minor}.0"
      MIM_BUILD_NUMBER=$((MIM_BUILD_NUMBER + 1))
      ;;
    major)
      major=$((major + 1))
      MIM_MARKETING_VERSION="${major}.0.0"
      MIM_BUILD_NUMBER=$((MIM_BUILD_NUMBER + 1))
      ;;
    *)
      echo "version: unknown bump kind '$kind' (build|patch|minor|major)" >&2
      return 1
      ;;
  esac

  mim_validate_semver "$MIM_MARKETING_VERSION"
  mim_validate_build_number "$MIM_BUILD_NUMBER"
  mim_write_version "$MIM_MARKETING_VERSION" "$MIM_BUILD_NUMBER"
  echo "==> Version bumped to $MIM_MARKETING_VERSION ($MIM_BUILD_NUMBER)" >&2
}

mim_apply_version_to_pubspec() {
  local root pubspec
  root="$(mim_repo_root)"
  pubspec="$root/pubspec.yaml"
  mim_read_version
  mim_validate_semver "$MIM_MARKETING_VERSION"
  mim_validate_build_number "$MIM_BUILD_NUMBER"
  python3 - "$pubspec" "$MIM_MARKETING_VERSION" "$MIM_BUILD_NUMBER" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
build = sys.argv[3]
text = path.read_text(encoding="utf-8")
pattern = re.compile(r"^version:\s+.+$", re.M)
if not pattern.search(text):
    raise SystemExit(f"version: no version field found in {path}")
next_text = pattern.sub(f"version: {version}+{build}", text, count=1)
path.write_text(next_text, encoding="utf-8")
PY
  echo "==> pubspec.yaml set to $MIM_MARKETING_VERSION+$MIM_BUILD_NUMBER" >&2
}

mim_dmg_filename() {
  mim_read_version
  echo "ProcessLama-${MIM_MARKETING_VERSION}-${MIM_BUILD_NUMBER}.dmg"
}

mim_linux_artifact_basename() {
  local arch="${1:-$(uname -m)}"
  mim_read_version
  echo "ProcessLama-${MIM_MARKETING_VERSION}-${MIM_BUILD_NUMBER}-linux-${arch}"
}

mim_linux_artifact_filename() {
  local format="$1"
  local arch="${2:-$(uname -m)}"
  local basename
  basename="$(mim_linux_artifact_basename "$arch")"
  case "$format" in
    appimage) echo "${basename}.AppImage" ;;
    deb) echo "${basename}.deb" ;;
    rpm) echo "${basename}.rpm" ;;
    tar) echo "${basename}.tar.gz" ;;
    *)
      echo "version: unknown Linux artifact format '$format'" >&2
      return 64
      ;;
  esac
}

mim_release_notes_html_filename() {
  mim_read_version
  echo "ProcessLama-${MIM_MARKETING_VERSION}-${MIM_BUILD_NUMBER}.html"
}

mim_release_tag_name() {
  mim_read_version
  echo "v${MIM_MARKETING_VERSION}-${MIM_BUILD_NUMBER}"
}
