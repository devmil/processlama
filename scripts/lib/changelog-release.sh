# shellcheck shell=bash
# Promote channel-specific CHANGELOG.md sections.

# shellcheck source=version.sh
source "$(dirname "${BASH_SOURCE[0]}")/version.sh"

mim_changelog_file() {
  echo "$(mim_repo_root)/CHANGELOG.md"
}

mim_finalize_markdown_release_file() {
  local file="$1"
  local kind="$2"
  local include_footers="$3"
  mim_read_version

  [[ -f "$file" ]] || {
    echo "$kind: missing $file" >&2
    return 1
  }

  local pending_label released_date repo_url
  released_date="$(date +%Y-%m-%d)"
  repo_url="${MIM_CHANGELOG_REPO_URL:-https://github.com/devmil/processlama}"
  case "${MIM_RELEASE_CHANNEL:-stable}" in
    beta) pending_label="Unreleased Beta" ;;
    stable) pending_label="Unreleased Stable" ;;
    *)
      echo "$kind: MIM_RELEASE_CHANNEL must be stable or beta" >&2
      return 1
      ;;
  esac

  python3 - "$file" "$kind" "$MIM_MARKETING_VERSION" "$MIM_BUILD_NUMBER" "$released_date" "$pending_label" "$repo_url" "$include_footers" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
kind = sys.argv[2]
version = sys.argv[3]
build = sys.argv[4]
released = sys.argv[5]
pending = sys.argv[6]
repo = sys.argv[7].rstrip("/")
include_footers = sys.argv[8] == "1"
tag = f"v{version}-{build}"
pending_labels = ("Unreleased Stable", "Unreleased Beta")

text = path.read_text(encoding="utf-8")
if not text.endswith("\n"):
    text += "\n"
text = re.sub(r"\n{2,}(?:\[[^\]]+\]:[^\n]*\n)+\s*$", "\n", text, flags=re.S)

def section_body(name):
    match = re.search(
        rf"^## \[{re.escape(name)}\][^\n]*\n(.*?)(?=^## \[|\Z)",
        text,
        re.M | re.S,
    )
    return match.group(1) if match else None

def has_substance(body):
    if not body:
        return False
    for line in body.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("###") and not stripped.startswith("["):
            return True
    return False

def split_footers(src):
    lines = src.splitlines(keepends=True)
    footer_start = len(lines)
    for index, line in enumerate(lines):
        if re.match(r"^\[[^\]]+\]:", line):
            footer_start = index
            break
    main = "".join(lines[:footer_start]).rstrip() + "\n"
    footers = {}
    for line in lines[footer_start:]:
        match = re.match(r"^\[([^\]]+)\]:\s*(.+)$", line.strip())
        if match:
            footers[match.group(1)] = match.group(2).strip()
    return main, footers

def clear_pending(main: str) -> str:
    labels = ("Unreleased Stable", "Unreleased Beta") if pending == "Unreleased Stable" else (pending,)
    for label in labels:
        main = re.sub(
            rf"^## \[{re.escape(label)}\][^\n]*\n.*?(?=^## \[|\Z)",
            f"## [{label}]\n\n",
            main,
            count=1,
            flags=re.M | re.S,
        )
    return main

def insert_release(main: str, body: str) -> str:
    release = f"## [{version}] - {released}\n\n{body.strip()}\n\n"
    if re.search(rf"^## \[{re.escape(version)}\]", main, re.M):
        return re.sub(
            rf"^## \[{re.escape(version)}\][^\n]*\n.*?(?=^## \[|\Z)",
            release,
            main,
            count=1,
            flags=re.M | re.S,
        )
    first_non_pending = None
    for match in re.finditer(r"^## \[([^\]]+)\]", main, re.M):
        if match.group(1) not in pending_labels:
            first_non_pending = match.start()
            break
    if first_non_pending is None:
        return main.rstrip() + "\n\n" + release
    return main[:first_non_pending].rstrip() + "\n\n" + release + main[first_non_pending:].lstrip()

body = section_body(pending)
existing = section_body(version)
if not has_substance(body) and not has_substance(existing):
    raise SystemExit(f"{kind}: add notes under ## [{pending}] or ## [{version}] in {path}")

main, footers = split_footers(text)
release_body = body if has_substance(body) else existing
main = clear_pending(main)
main = insert_release(main, release_body or "")

if include_footers:
    footers.pop("Unreleased", None)
    for label in pending_labels:
        footers[label] = f"{repo}/compare/{tag}...HEAD"
    footers[version] = f"{repo}/releases/tag/{tag}"
    order = []
    for label in pending_labels:
        if label in footers:
            order.append(label)
    for match in re.finditer(r"^## \[([^\]]+)\]", main, re.M):
        name = match.group(1)
        if name in footers and name not in order:
            order.append(name)
    for key in footers:
        if key not in order:
            order.append(key)
    footer_text = "\n".join(f"[{key}]: {footers[key]}" for key in order)
    output = main.rstrip() + "\n\n\n" + footer_text + "\n"
else:
    output = main.rstrip() + "\n"

path.write_text(output, encoding="utf-8")
print(f"{kind}: promoted [{pending}] -> ## [{version}] - {released}", file=sys.stderr)
PY
}

mim_finalize_changelog_for_release() {
  mim_finalize_markdown_release_file "$(mim_changelog_file)" "changelog-release" 1
}
