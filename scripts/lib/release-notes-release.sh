# shellcheck shell=bash
# Promote channel-specific RELEASE_NOTES.md sections.

# shellcheck source=changelog-release.sh
source "$(dirname "${BASH_SOURCE[0]}")/changelog-release.sh"

mim_release_notes_file() {
  echo "$(mim_repo_root)/RELEASE_NOTES.md"
}

mim_finalize_release_notes_for_release() {
  mim_finalize_markdown_release_file "$(mim_release_notes_file)" "release-notes-release" 0
}
