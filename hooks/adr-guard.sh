#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit): the first time a session
# edits inside an area governed by ADRs, injects the list of those ADRs.
#
# Which ADRs govern a file is decided by path only, with no assumption about
# the repo's layout: every ADR has an owner directory (the directory that holds
# its ADR folder, skipping a docs container such as docs/ or .ai/), and it
# applies to
#   1. every file under its owner directory (the repo root owns repo-wide ADRs)
#   2. every file whose path has a segment named like the owner directory
#      (so tests kept in a parallel tree still get their module's ADRs).
# Silent in repos without ADRs.
set -uo pipefail

here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
session="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$file" ] || exit 0

case "$file" in /*) ;; *) file="${cwd:-$PWD}/$file" ;; esac
case "$file" in *.md|*.txt|*.lock) exit 0 ;; esac

# The file may not exist yet: walk up to the nearest existing directory.
dir="$(dirname "$file")"
while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do dir="$(dirname "$dir")"; done
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
# git prints the physical root; resolve symlinks in the file path the same way.
file="$(cd -P "$dir" && pwd -P)${file#"$dir"}"

all="$("$here/list-adrs.sh" "$root" 2>/dev/null)"
[ -n "$all" ] || exit 0

rel="${file#"$root"/}"
state="${TMPDIR:-/tmp}/rstack-adr-guard/$session/$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
mkdir -p "$state" 2>/dev/null || exit 0

# Owner directory of an ADR path: drop the file, the ADR folder, and a docs
# container directly above it. Empty string = repo root.
owner_of() {
  local d
  d="$(dirname "$(dirname "$1")")"
  case "$(basename "$d")" in .ai|docs|doc|documentation|.github) d="$(dirname "$d")" ;; esac
  [ "$d" = "." ] && d=""
  printf '%s' "$d"
}

title() { grep -m1 -E '^# ' "$root/$1" 2>/dev/null | sed -E 's/^# +//'; }

out=""
shown=""
while IFS= read -r adr; do
  [ -n "$adr" ] || continue
  owner="$(owner_of "$adr")"
  if [ -z "$owner" ]; then
    applies=1
  else
    case "$rel" in
      "$owner"/*) applies=1 ;;
      *) case "/$rel" in */"$(basename "$owner")"/*) applies=1 ;; *) applies=0 ;; esac ;;
    esac
  fi
  [ "$applies" = 1 ] || continue

  key="$state/$(printf '%s' "${owner:-.}" | cksum | cut -d' ' -f1)"
  # Already announced in this session, unless it was announced by this very call.
  if [ -e "$key" ]; then
    case " $shown " in *" $key "*) ;; *) continue ;; esac
  else
    : > "$key"
    shown="$shown $key"
    out+=$'\n'"ADRs owned by ${owner:-the repo root (apply to every change)}:"$'\n'
  fi
  out+="- $adr — $(title "$adr")"$'\n'
done <<EOF
$(printf '%s\n' "$all" | awk '{ n=split($0,a,"/"); print n "\t" $0 }' | sort -k1,1nr -k2 | cut -f2-)
EOF

[ -n "$out" ] || exit 0

msg="[rstack adr-guard] First edit in this area this session (${rel}). Paths are relative to ${root}."$'\n'"${out}"$'\n'"Read in full each one you have not read in this session, then check the change you are about to make against it. If it contradicts an ADR, stop and tell the user which rule and why instead of editing."

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
