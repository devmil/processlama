# shellcheck shell=bash
# Git hygiene, release commit, and tag helpers.

# shellcheck source=version.sh
source "$(dirname "${BASH_SOURCE[0]}")/version.sh"

mim_require_clean_for_release() {
  local root line path status_code=0
  root="$(mim_repo_root)"
  cd "$root"
  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "release-git: not a git repository" >&2
    return 1
  }
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    path="${line:3}"
    if [[ "$path" == "CHANGELOG.md" || "$path" == "RELEASE_NOTES.md" ]]; then
      continue
    fi
    echo "release-git: uncommitted change not allowed before release: $path" >&2
    status_code=1
  done < <(git status --porcelain --untracked-files=no)
  if [[ "$status_code" -ne 0 ]]; then
    echo "release-git: commit or stash other work first; CHANGELOG.md and RELEASE_NOTES.md may remain edited." >&2
    return 1
  fi
  echo "==> Git working tree clean for release." >&2
}

mim_commit_release_artifacts() {
  local root subject body
  root="$(mim_repo_root)"
  cd "$root"
  mim_read_version

  local -a paths=(
    VERSION
    CHANGELOG.md
    RELEASE_NOTES.md
    pubspec.yaml
  )

  local missing=0
  for p in "${paths[@]}"; do
    [[ -e "$root/$p" ]] || {
      echo "release-git: missing release file: $p" >&2
      missing=1
    }
  done
  [[ "$missing" -eq 0 ]] || return 1

  git add "${paths[@]}"
  if git diff --cached --quiet; then
    echo "release-git: nothing to commit" >&2
    return 1
  fi

  if [[ "${MIM_RELEASE_CHANNEL:-stable}" == "beta" ]]; then
    subject="Beta release v${MIM_MARKETING_VERSION} (build ${MIM_BUILD_NUMBER})"
  else
    subject="Release v${MIM_MARKETING_VERSION} (build ${MIM_BUILD_NUMBER})"
  fi
  body="Prepared the platform-neutral ${MIM_RELEASE_CHANNEL:-stable} release metadata. Platform bundles are built and published from the resulting tag."
  git commit -m "$subject" -m "$body"
  echo "==> Created release commit: $subject" >&2
}

mim_require_release_tag_checkout() {
  local expected_tag="$1"
  local root tag_commit head_commit
  root="$(mim_repo_root)"
  cd "$root"
  git rev-parse --verify "refs/tags/$expected_tag" >/dev/null 2>&1 || {
    echo "release-git: release tag '$expected_tag' does not exist locally" >&2
    return 1
  }
  tag_commit="$(git rev-list -n 1 "$expected_tag")"
  head_commit="$(git rev-parse HEAD)"
  git merge-base --is-ancestor "$tag_commit" "$head_commit" || {
    echo "release-git: HEAD ($head_commit) does not descend from release tag $expected_tag ($tag_commit)" >&2
    return 1
  }
  if [[ -n "$(git diff --name-only "$expected_tag"..HEAD -- . ':(exclude)website/**')" ]]; then
    echo "release-git: non-website source changed after $expected_tag; build from the tag or its bundle-publication commits only" >&2
    git diff --name-only "$expected_tag"..HEAD -- . ':(exclude)website/**' >&2
    return 1
  fi
  [[ -z "$(git status --porcelain)" ]] || {
    echo "release-git: bundle publication requires a clean checkout" >&2
    git status --short >&2
    return 1
  }
}

mim_commit_bundle_artifacts() {
  local platform="$1"
  shift
  local root tag subject
  root="$(mim_repo_root)"
  cd "$root"
  tag="$(mim_release_tag_name)"
  git add website/releases.html website/_data/releases.json "$@"
  if [[ "$platform" == "macos" ]]; then
    git add website/download/appcast.xml
  fi
  if git diff --cached --quiet; then
    echo "release-git: no $platform bundle changes to commit" >&2
    return 1
  fi
  subject="Publish ${platform} bundles for ${tag}"
  git commit -m "$subject" -m "Built the ${platform} artifacts from the immutable $tag release tag and published their website metadata."
  echo "==> Created bundle publication commit: $subject" >&2
}

mim_create_release_git_tag() {
  local root tag message
  root="$(mim_repo_root)"
  cd "$root"
  tag="$(mim_release_tag_name)"
  if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "release-git: tag $tag already exists" >&2
    return 1
  fi
  if ! git diff --quiet --ignore-submodules || ! git diff --cached --quiet --ignore-submodules; then
    echo "release-git: working tree is not clean after release commit" >&2
    git status --short >&2
    return 1
  fi
  message="ProcessLama ${MIM_MARKETING_VERSION} (build ${MIM_BUILD_NUMBER})"
  git tag -a "$tag" -m "$message"
  echo "==> Created git tag $tag" >&2
}

mim_resolve_existing_release_commit() {
  local root tag tag_commit head_commit current_pubspec_version tag_pubspec_version subject path
  root="$(mim_repo_root)"
  cd "$root"
  mim_read_version
  tag="$(mim_release_tag_name)"
  [[ -z "$(git status --porcelain)" ]] || {
    echo "release-git: resume requires a clean committed checkout" >&2
    return 1
  }
  head_commit="$(git rev-parse HEAD)"
  if git show-ref --verify --quiet "refs/tags/$tag"; then
    git rev-parse --verify "refs/tags/$tag^{tag}" >/dev/null 2>&1 || {
      echo "release-git: resume requires existing annotated tag $tag" >&2
      return 1
    }
    tag_commit="$(git rev-list -n 1 "$tag")"
  else
    # Publication creates the tag only after every target succeeds. A failed
    # target therefore leaves a prepared release commit without a tag.
    tag_commit="$(git log -1 --format=%H -- VERSION)"
    subject="$(git show -s --format=%s "$tag_commit")"
    case "$subject" in
      "Release v${MIM_MARKETING_VERSION} (build ${MIM_BUILD_NUMBER})" | \
      "Beta release v${MIM_MARKETING_VERSION} (build ${MIM_BUILD_NUMBER})") ;;
      *)
        echo "release-git: no prepared release commit for $tag" >&2
        return 1
        ;;
    esac
    for path in VERSION pubspec.yaml CHANGELOG.md RELEASE_NOTES.md; do
      git diff --quiet "$tag_commit" HEAD -- "$path" || {
        echo "release-git: $path changed after release preparation" >&2
        return 1
      }
    done
    echo "==> Resuming untagged prepared release $tag from $tag_commit" >&2
  fi
  git merge-base --is-ancestor "$tag_commit" "$head_commit" || {
    echo "release-git: current main does not descend from $tag" >&2
    return 1
  }
  [[ "$(git show "$tag_commit:VERSION")" == "$(cat VERSION)" ]] || {
    echo "release-git: VERSION no longer agrees with $tag" >&2
    return 1
  }
  current_pubspec_version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml)"
  tag_pubspec_version="$(git show "$tag_commit:pubspec.yaml" | sed -n 's/^version:[[:space:]]*//p')"
  [[ "$current_pubspec_version" == "$MIM_MARKETING_VERSION+$MIM_BUILD_NUMBER" ]] || {
    echo "release-git: pubspec.yaml does not agree with VERSION" >&2
    return 1
  }
  [[ "$tag_pubspec_version" == "$current_pubspec_version" ]] || {
    echo "release-git: pubspec.yaml no longer agrees with $tag" >&2
    return 1
  }
  python3 - "$MIM_MARKETING_VERSION" CHANGELOG.md RELEASE_NOTES.md <<'PY'
import re
import sys
from pathlib import Path

version = sys.argv[1]
for name in sys.argv[2:]:
    path = Path(name)
    text = path.read_text(encoding="utf-8")
    match = re.search(
        rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## \[|\Z)",
        text,
        re.M | re.S,
    )
    body = match.group(1) if match else ""
    if not any(
        line.strip()
        and not line.strip().startswith("###")
        and not line.strip().startswith("[")
        for line in body.splitlines()
    ):
        raise SystemExit(f"release-git: {path} has no released [{version}] notes")
PY
  printf '%s\n' "$tag_commit"
}
