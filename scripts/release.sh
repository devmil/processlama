#!/usr/bin/env bash
# Prepare platform-neutral release metadata, commit it, and create an immutable tag.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIM_REPO_ROOT="$ROOT"

# shellcheck source=lib/version.sh
source "$ROOT/scripts/lib/version.sh"
# shellcheck source=lib/release-channel.sh
source "$ROOT/scripts/lib/release-channel.sh"
# shellcheck source=lib/changelog-release.sh
source "$ROOT/scripts/lib/changelog-release.sh"
# shellcheck source=lib/release-notes-release.sh
source "$ROOT/scripts/lib/release-notes-release.sh"
# shellcheck source=lib/release-git.sh
source "$ROOT/scripts/lib/release-git.sh"

MIM_RELEASE_CHANNEL=""
MIM_BUMP=""
MIM_SET_VERSION=""
MIM_SET_BUILD=""
MIM_CHANGELOG_CHECK=1
MIM_GIT_COMMIT=1
MIM_GIT_TAG=1
MIM_VERIFY=1
MIM_ALLOW_DIRTY=0

usage() {
  cat <<'EOF'
ProcessLama release preparation

Creates the version/release-note commit and immutable tag. It never builds or
publishes a platform bundle; run publish-bundle.sh on each platform afterwards.

Examples:
  ./scripts/release.sh --channel stable --bump patch
  ./scripts/release.sh --channel beta --bump beta
  ./scripts/release.sh --channel stable --version 1.2.0 --build 17

Options:
  --channel stable|beta              Required release track
  --bump build|beta|promote|patch|minor|major
  --version X.Y.Z[-beta.N|-rc.N]     Set marketing version
  --build N                          Set monotonic build number
  --no-verify                        Skip ./scripts/verify.sh
  --no-changelog-check               Skip changelog/release-note promotion
  --no-git-commit                    Do not create a release commit or tag
  --no-git-tag                       Do not create the git tag
  --allow-dirty                      Local rehearsal only
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) shift; MIM_RELEASE_CHANNEL="${1:?--channel requires stable|beta}"; export MIM_RELEASE_CHANNEL ;;
    --bump) shift; MIM_BUMP="${1:?--bump requires a value}" ;;
    --version) shift; MIM_SET_VERSION="${1:?--version requires a value}" ;;
    --build) shift; MIM_SET_BUILD="${1:?--build requires a value}" ;;
    --no-verify) MIM_VERIFY=0 ;;
    --no-changelog-check) MIM_CHANGELOG_CHECK=0 ;;
    --no-git-commit) MIM_GIT_COMMIT=0; MIM_GIT_TAG=0 ;;
    --no-git-tag) MIM_GIT_TAG=0 ;;
    --allow-dirty) MIM_ALLOW_DIRTY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "release.sh: unknown option $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

cd "$ROOT"
mim_require_release_channel
if [[ "$MIM_ALLOW_DIRTY" -eq 0 ]]; then
  mim_require_clean_for_release
else
  echo "==> Skipping clean-tree check (--allow-dirty)" >&2
fi

[[ -z "$MIM_BUMP" ]] || mim_bump_release_channel_version "$MIM_BUMP"
if [[ -n "$MIM_SET_VERSION" || -n "$MIM_SET_BUILD" ]]; then
  mim_read_version
  [[ -z "$MIM_SET_VERSION" ]] || MIM_MARKETING_VERSION="$MIM_SET_VERSION"
  [[ -z "$MIM_SET_BUILD" ]] || MIM_BUILD_NUMBER="$MIM_SET_BUILD"
  mim_validate_semver "$MIM_MARKETING_VERSION"
  mim_validate_build_number "$MIM_BUILD_NUMBER"
  mim_write_version "$MIM_MARKETING_VERSION" "$MIM_BUILD_NUMBER"
fi

mim_read_version
mim_validate_release_channel_version
mim_validate_release_build_monotonicity
mim_apply_version_to_pubspec
if [[ "$MIM_CHANGELOG_CHECK" -eq 1 ]]; then
  mim_finalize_changelog_for_release
  mim_finalize_release_notes_for_release
fi
[[ "$MIM_VERIFY" -eq 0 ]] || ./scripts/verify.sh
[[ "$MIM_GIT_COMMIT" -eq 0 ]] || mim_commit_release_artifacts
[[ "$MIM_GIT_TAG" -eq 0 ]] || mim_create_release_git_tag

tag_name="$(mim_release_tag_name)"
echo
echo "Release ${MIM_MARKETING_VERSION} (${MIM_BUILD_NUMBER}) prepared."
echo "  Tag: $tag_name"
echo "  Push release commit and tag, then publish bundles from tagged checkouts:"
echo "    git push origin main && git push origin $tag_name"
  echo "    ./scripts/publish-bundle.sh --tag $tag_name --platform linux"
  echo "    ./scripts/publish-bundle.sh --tag $tag_name --platform macos"
  echo "  Windows ZIP and MSI bundles are built by the GitHub Actions release workflow."
