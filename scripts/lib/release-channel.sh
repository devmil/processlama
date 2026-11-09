# shellcheck shell=bash
# Stable/beta release channel validation.

# shellcheck source=version.sh
source "$(dirname "${BASH_SOURCE[0]}")/version.sh"

mim_require_release_channel() {
  [[ -n "${MIM_RELEASE_CHANNEL:-}" ]] || {
    echo "release-channel: --channel stable|beta is required" >&2
    return 1
  }
  case "$MIM_RELEASE_CHANNEL" in
    stable | beta) ;;
    *)
      echo "release-channel: unknown channel '$MIM_RELEASE_CHANNEL' (expected stable or beta)" >&2
      return 1
      ;;
  esac
}

mim_is_prerelease_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+-.+ ]]
}

mim_is_beta_channel_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+|-rc\.[0-9]+)$ ]]
}

mim_is_beta_prerelease_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.([0-9]+)$ ]]
}

mim_base_version() {
  echo "${1%%-*}"
}

mim_bump_release_channel_version() {
  local kind="${1:-build}"
  if [[ "$kind" == "beta" && "${MIM_RELEASE_CHANNEL:-}" != "beta" ]]; then
    echo "release-channel: --bump beta requires --channel beta" >&2
    return 1
  fi
  if [[ "$kind" == "promote" ]]; then
    if [[ "${MIM_RELEASE_CHANNEL:-}" != "stable" ]]; then
      echo "release-channel: --bump promote requires --channel stable" >&2
      return 1
    fi
    mim_read_version
    if ! mim_is_beta_channel_version "$MIM_MARKETING_VERSION"; then
      echo "release-channel: --bump promote requires a beta or RC version" >&2
      return 1
    fi
    mim_write_version "$(mim_base_version "$MIM_MARKETING_VERSION")" \
      "$((MIM_BUILD_NUMBER + 1))"
    echo "==> Version promoted to $MIM_MARKETING_VERSION ($MIM_BUILD_NUMBER)" >&2
    return 0
  fi

  if [[ "${MIM_RELEASE_CHANNEL:-}" != "beta" || "$kind" == "build" ]]; then
    mim_bump_version "$kind"
    return $?
  fi

  mim_read_version
  mim_validate_semver "$MIM_MARKETING_VERSION"
  mim_validate_build_number "$MIM_BUILD_NUMBER"

  if [[ "$kind" == "beta" ]]; then
    if ! mim_is_beta_prerelease_version "$MIM_MARKETING_VERSION"; then
      echo "release-channel: --channel beta --bump beta requires VERSION to already contain -beta.N" >&2
      return 1
    fi
    local base beta_number
    base="$(mim_base_version "$MIM_MARKETING_VERSION")"
    beta_number="${BASH_REMATCH[1]}"
    mim_write_version "${base}-beta.$((beta_number + 1))" "$((MIM_BUILD_NUMBER + 1))"
    echo "==> Version bumped to $MIM_MARKETING_VERSION ($MIM_BUILD_NUMBER)" >&2
    return 0
  fi

  local major minor patch
  IFS='.' read -r major minor patch <<<"${MIM_MARKETING_VERSION%%-*}"
  patch="${patch%%+*}"
  case "$kind" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *)
      echo "version: unknown bump kind '$kind' (build|beta|promote|patch|minor|major)" >&2
      return 1
      ;;
  esac
  mim_write_version "${major}.${minor}.${patch}-beta.1" "$((MIM_BUILD_NUMBER + 1))"
  echo "==> Version bumped to $MIM_MARKETING_VERSION ($MIM_BUILD_NUMBER)" >&2
}

mim_validate_release_channel_version() {
  mim_read_version
  case "$MIM_RELEASE_CHANNEL" in
    stable)
      if mim_is_prerelease_version "$MIM_MARKETING_VERSION"; then
        echo "release-channel: stable releases cannot use prerelease version '$MIM_MARKETING_VERSION'" >&2
        return 1
      fi
      ;;
    beta)
      if ! mim_is_beta_channel_version "$MIM_MARKETING_VERSION"; then
        echo "release-channel: beta releases require -beta.N or -rc.N (got '$MIM_MARKETING_VERSION')" >&2
        return 1
      fi
      ;;
  esac
}

mim_collect_known_build_numbers() {
  local root data_file appcast_file
  root="$(mim_repo_root)"
  data_file="$root/website/_data/releases.json"
  appcast_file="$root/website/download/appcast.xml"
  python3 - "$data_file" "$appcast_file" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

data_path = Path(sys.argv[1])
appcast_path = Path(sys.argv[2])
builds = set()

if data_path.exists():
    data = json.loads(data_path.read_text(encoding="utf-8"))
    for item in [data.get("latest"), *(data.get("history") or [])]:
        if item and item.get("build") is not None:
            builds.add(int(item["build"]))
    beta = data.get("beta") or {}
    for item in [beta.get("latest"), *(beta.get("history") or [])]:
        if item and item.get("build") is not None:
            builds.add(int(item["build"]))

if appcast_path.exists():
    ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
    tree = ET.parse(appcast_path)
    for item in tree.getroot().findall("./channel/item"):
        version_el = item.find("sparkle:version", ns)
        if version_el is not None and (version_el.text or "").strip().isdigit():
            builds.add(int(version_el.text.strip()))

print(" ".join(str(build) for build in sorted(builds)))
PY
}

mim_validate_release_build_monotonicity() {
  mim_read_version
  local known max_build=0 build
  known="$(mim_collect_known_build_numbers)"
  for build in $known; do
    [[ "$build" -gt "$max_build" ]] && max_build="$build"
  done
  if [[ "$MIM_BUILD_NUMBER" -le "$max_build" ]]; then
    echo "release-channel: build $MIM_BUILD_NUMBER must be greater than highest shipped build ($max_build)" >&2
    return 1
  fi
}
