#!/usr/bin/env bash
# A real reset of a project's coordinator (#446; macOS / Linux; Windows: reset-coordinator.ps1 - the same arguments, messages, codes).
#   scripts/reset-coordinator.sh --root <project root> --confirm <the project folder's name> --core-from <a clean clone of claude-coordinator>
# Only on the owner's own words: procedures/RESET.md. Every check comes before anything changes. Then all of coordinator/ (ignored files
# too, raw bytes) and the project's auto-memory go behind the tag before-reset-<date>, pushed where there is a remote; coordinator/ then
# holds only .git and core/, a copy of the clone; the memory folder is emptied. The project's own repository is never touched.
# Exit 0 with `reset-coordinator: done tag=<tag> core=<sha>`; 1 a refusal, nothing changed, or a failed step, named; 2 a usage error.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
no() { echo "reset-coordinator: refused: $*" >&2; exit 1; }
failed() { echo "reset-coordinator: FAILED: $*" >&2; exit 1; }
usage() { echo "usage: scripts/reset-coordinator --root <project root> --confirm <the project folder's name> --core-from <a clean clone of claude-coordinator>" >&2; exit 2; }
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
root="" confirm="" from=""
while [ $# -gt 0 ]; do [ $# -ge 2 ] || usage
  case "$1" in --root) root="$2" ;; --confirm) confirm="$2" ;; --core-from) from="$2" ;; *) usage ;; esac; shift 2
done
[ -n "$root" ] || usage; [ -d "$root" ] || no "--root is not a folder: $root"
root="$(w "$(cd "$root" && pwd -P)")"
# THE GUARD: first, read from files, whatever was typed
if [ -f "$root/CORE.md" ] && [ -f "$root/scripts/check-core.sh" ]; then no "$root is the core's own repository (it holds CORE.md and scripts/check-core.sh): it is never reset"; fi
[ "$confirm" = "${root##*/}" ] || no "--confirm must be this project's folder name, ${root##*/}"
st="$root/coordinator"
[ -e "$st/.git" ] || no "no state repository: $st/.git is missing"
[ -z "$(ls -A "$st/assistants" 2>/dev/null)" ] || no "coordinator/assistants is not empty: only the owner's word naming an assistant removes it (coord-assistant) (CORE section 8)"
{ [ -n "$from" ] && [ -d "$from" ]; } || no "--core-from must be a clean clone of claude-coordinator: $from"
from="$(w "$(cd "$from" && pwd -P)")"
case "$from/" in "$st"/*) no "--core-from must be a clean clone outside coordinator/: $from" ;; esac
{ [ -e "$from/.git" ] && [ -f "$from/CORE.md" ] && [ -f "$from/scripts/check-core.sh" ]; } || no "--core-from must be a clean clone of claude-coordinator: $from"
sha="$(git -C "$from" rev-parse HEAD 2>/dev/null)" && d="$(git -C "$from" status --porcelain 2>&1)" && [ -z "$d" ] || no "--core-from must be a clean clone of claude-coordinator: $from"
# From here the cwd is the root: never a folder this replaces, and gh reads the project's repository. No remote of its own: no PR can exist
cd "$root" || no "cannot enter $root"
prs="$(gh pr list --json number 2>/dev/null)" || { [ -z "$(git remote 2>/dev/null)" ] || no "cannot read the project's open PRs: gh failed"; prs='[]'; }
printf '%s' "$prs" | tr -d ' \t\r\n' | grep -q '^\[.*\]$' || no "cannot read the project's open PRs: gh printed no JSON list"
open="$(printf '%s' "$prs" | grep -o '"number": *[0-9]*' | sed 's/.*: */#/' | tr '\n' ' ')"
[ -z "$open" ] || no "open PR of the project: ${open% }"
sess="$(claude agents --json --all 2>/dev/null)" && printf '%s' "$sess" | tr -d ' \t\r\n' | grep -q '^\[.*\]$' || no "cannot read the running sessions: claude agents failed"
ci=""; command -v cygpath >/dev/null 2>&1 && ci=1
# one object per line, the free text of a name out of the way; running = state working, or a status field
running="$(printf '%s\n' "$sess" | grep -v '^ *"name":' | tr -d '\r\n' | tr '}' '\n' | ROOT="$root" ME="${CLAUDE_CODE_SESSION_ID:-}" CI="$ci" LC_ALL=C awk '
  function f(k, v) { if (!match($0, "\"" k "\": *\"[^\"]*\"")) return ""; v = substr($0, RSTART, RLENGTH); sub(/^"[^"]*": *"/, "", v); return substr(v, 1, length(v) - 1) }
  { c = f("cwd"); gsub(/\\\\/, "/", c); r = ENVIRON["ROOT"]; if (ENVIRON["CI"] != "") { c = tolower(c); r = tolower(r) }
    if (f("id") == "" || f("sessionId") == ENVIRON["ME"] || (f("state") != "working" && !index($0, "\"status\":"))) next
    if (c == r || substr(c, 1, length(r) + 1) == r "/") print f("id") }' | tr '\n' ' ')"
[ -z "$running" ] || no "running session of the project: ${running% }"
tag="before-reset-$(date +%Y-%m-%d)"
parent="$(git -C "$st" rev-parse -q --verify HEAD)" || no "the state repository has no commit: $st"
git -C "$st" rev-parse -q --verify "refs/tags/$tag" >/dev/null && no "the tag $tag already exists: one reset a day"
remote="$(git -C "$st" remote | grep -x origin || git -C "$st" remote | head -n 1)"
[ -z "$remote" ] || git -C "$st" push --dry-run -q "$remote" HEAD >/dev/null 2>&1 || no "the state repository's remote $remote cannot be reached or does not take its branch"
[ -z "$remote" ] || [ -z "$(git -C "$st" ls-remote --tags "$remote" "refs/tags/$tag" 2>/dev/null)" ] || no "the tag $tag already exists on the remote: one reset a day"
# The tag's commit, on no branch until pushed. Raw bytes: a throwaway git dir's info/attributes beats core/'s `* text=auto`, a new index reads a stat-clean CRLF file again.
t="$(w "$(mktemp -d)")"; trap 'rm -rf "$t"' EXIT
gd="$(git -C "$st" rev-parse --absolute-git-dir)" && git init -q --template= "$t/g" || no "cannot prepare the tag"
mkdir -p "$t/g/.git/info"; echo '* -text' > "$t/g/.git/info/attributes"
tree_of() { GIT_DIR="$t/g/.git" GIT_WORK_TREE="$1" GIT_OBJECT_DIRECTORY="$gd/objects" GIT_INDEX_FILE="$2" git -C "$1" -c core.autocrlf=false add -A -f . >/dev/null 2>&1 &&
  GIT_DIR="$t/g/.git" GIT_OBJECT_DIRECTORY="$gd/objects" GIT_INDEX_FILE="$2" git write-tree; }
tree_of "$st" "$t/i" >/dev/null || no "the tag $tag: cannot read coordinator/"
pdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$root" | sed 's/[^A-Za-z0-9]/-/g')"; mem="$pdir/memory"
if [ -n "$(ls -A "$mem" 2>/dev/null)" ]; then
  mt="$(tree_of "$mem" "$t/m")" && GIT_INDEX_FILE="$t/i" git -C "$st" read-tree --prefix=before-reset-memory/ "$mt" || no "the tag $tag: cannot read the memory folder $mem"
fi
tree="$(GIT_INDEX_FILE="$t/i" git -C "$st" write-tree)" && commit="$(git -C "$st" commit-tree "$tree" -p "$parent" -m "before reset: $tag")" || no "the tag $tag: cannot commit (git's user set?)"
git -C "$st" tag "$tag" "$commit" || no "the tag $tag cannot be made"
[ -z "$remote" ] || git -C "$st" push -q "$remote" "refs/tags/$tag" >/dev/null 2>&1 || { git -C "$st" tag -d "$tag" >/dev/null 2>&1; no "the tag $tag cannot be pushed to $remote"; }
# Parked first, by rename: a held file or folder (Windows) stops it here, all put back. A running script keeps reading the parked file; the new core goes to new files.
old="$st/.reset-old"; parked=""; mkdir "$old" || failed "cannot make $old; the tag $tag is made"
while IFS= read -r e; do case "$e" in .git|.reset-old|"") continue ;; esac
  mv "$st/$e" "$old/$e" 2>/dev/null && { parked="$parked $e"; continue; }
  for p in $parked; do mv "$old/$p" "$st/$p"; done; rmdir "$old"; git -C "$st" tag -d "$tag" >/dev/null 2>&1
  [ -z "$remote" ] || git -C "$st" push -q "$remote" ":refs/tags/$tag" >/dev/null 2>&1
  no "coordinator/$e is held by another process: nothing removed, the tag taken back"
done <<EOF
$(ls -A "$st")
EOF
git -C "$st" update-ref HEAD "$commit" || failed "cannot move the state branch; everything is in $old and behind the tag $tag"
rm -rf "$old" && rm -rf "$mem" || failed "cannot remove $old or $mem; everything is behind the tag $tag"; [ ! -d "$pdir" ] || mkdir -p "$mem"
mkdir "$st/core" && find "$from" -mindepth 1 -maxdepth 1 ! -name .git ! -name .github ! -name CLAUDE.md -exec cp -R {} "$st/core/" \; || failed "cannot copy the core from $from; everything is behind the tag $tag"
git -C "$st" read-tree --empty && git -C "$st" add -A >/dev/null 2>&1 && tree="$(git -C "$st" write-tree)" && c2="$(git -C "$st" commit-tree "$tree" -p "$commit" -m "reset of the coordinator: tag=$tag core=$sha")" &&
  git -C "$st" update-ref HEAD "$c2" || failed "cannot commit the new state in $st; everything is behind the tag $tag"
if [ -z "$remote" ]; then echo "reset-coordinator: no remote: the tag is local only"; elif ! git -C "$st" push -q "$remote" HEAD >/dev/null 2>&1; then echo "reset-coordinator: the state branch is not pushed yet: git -C coordinator push $remote HEAD"; fi
echo "reset-coordinator: done tag=$tag core=$sha"
