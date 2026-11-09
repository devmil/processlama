# shellcheck shell=bash
# Publish platform artifacts into website/download and render release pages.

# shellcheck source=version.sh
source "$(dirname "${BASH_SOURCE[0]}")/version.sh"
# shellcheck source=release-notes-release.sh
source "$(dirname "${BASH_SOURCE[0]}")/release-notes-release.sh"

mim_website_download_dir() { echo "$(mim_repo_root)/website/download"; }
mim_website_releases_data() { echo "$(mim_repo_root)/website/_data/releases.json"; }
mim_website_release_url_prefix() { echo "${MIM_RELEASE_URL_PREFIX:-https://devmil.de/processlama/download/}"; }

mim_write_release_notes_html() {
  local version="$1"
  local dest_file="$2"
  python3 "$(mim_repo_root)/scripts/lib/website_release.py" notes \
    --notes "$(mim_release_notes_file)" --version "$version" --output "$dest_file"
}

mim_render_releases_page() {
  python3 "$(mim_repo_root)/scripts/lib/website_release.py" render \
    --data "$(mim_website_releases_data)" \
    --output "$(mim_repo_root)/website/releases.html"
}

mim_publish_artifact_to_website() {
  local source_file="$1"
  local platform="$2"
  local format="$3"
  local architectures="$4"
  local minimum_system="${5:-}"
  local download_url="${6:-}"
  local sparkle_signature="${7:-}"
  [[ -f "$source_file" ]] || {
    echo "website-release: artifact not found: $source_file" >&2
    return 1
  }
  mim_read_version
  local download_dir data_file filename destination notes_name
  download_dir="$(mim_website_download_dir)"
  data_file="$(mim_website_releases_data)"
  filename="$(basename "$source_file")"
  destination="$download_dir/$filename"
  notes_name="$(mim_release_notes_html_filename)"
  mkdir -p "$download_dir" "$(dirname "$data_file")"
  cp "$source_file" "$destination"
  mim_write_release_notes_html "$MIM_MARKETING_VERSION" "$download_dir/$notes_name"
  local -a optional_args=()
  [[ -z "$download_url" ]] || optional_args+=(--download-url "$download_url")
  [[ -z "$sparkle_signature" ]] || optional_args+=(--sparkle-signature "$sparkle_signature")
  python3 "$(mim_repo_root)/scripts/lib/website_release.py" publish \
    --data "$data_file" --version "$MIM_MARKETING_VERSION" \
    --build "$MIM_BUILD_NUMBER" --channel "$MIM_RELEASE_CHANNEL" \
    --artifact "$destination" --platform "$platform" --format "$format" \
    --architectures "$architectures" --minimum-system "$minimum_system" \
    --notes-path "/download/$notes_name" "${optional_args[@]}"
  mim_render_releases_page
  echo "==> Published $platform/$format for $MIM_MARKETING_VERSION ($MIM_BUILD_NUMBER)" >&2
}

mim_publish_release_to_website() {
  mim_publish_artifact_to_website "$1" macos dmg "Apple Silicon & Intel" "macOS 14.0"
}
