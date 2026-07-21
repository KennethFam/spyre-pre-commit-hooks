#!/usr/bin/env bash
# check_submodules.sh
#
# For every submodule declared in .gitmodules:
#   - Warns if the pinned commit is behind the remote HEAD.
#   - If the submodule path matches AUTO_UPDATE_SUBMODULE (default: "common"),
#     automatically runs `git submodule update --remote <path>` and stages the
#     updated pointer so the bump is included in the current commit.
#   - All other stale submodules receive a warning only.
#
# Always exits 0 — this hook never blocks a commit.
#
# Optional env vars
#   SUBMODULE_REMOTE_BRANCH   Remote ref to compare against (default: HEAD)
#   SUBMODULE_SKIP            Space-separated list of submodule paths to skip
#   AUTO_UPDATE_SUBMODULE     Submodule path to auto-update (default: common)

set -euo pipefail

REMOTE_BRANCH="${SUBMODULE_REMOTE_BRANCH:-HEAD}"
SKIP_LIST="${SUBMODULE_SKIP:-}"
AUTO_UPDATE="${AUTO_UPDATE_SUBMODULE:-common}"

# ── Collect all submodule paths from .gitmodules ─────────────────────────────
if [[ ! -f .gitmodules ]]; then
  exit 0  # No submodules in this repo — nothing to do
fi

submodule_paths=()
while IFS= read -r line; do
  submodule_paths+=("$line")
done < <(git config --file .gitmodules --get-regexp '\.path$' | awk '{print $2}')

if [[ ${#submodule_paths[@]} -eq 0 ]]; then
  exit 0
fi

# ── Check each submodule ──────────────────────────────────────────────────────
warned=0

for path in "${submodule_paths[@]}"; do

  # Honour the skip list
  for skip in $SKIP_LIST; do
    if [[ "$path" == "$skip" ]]; then
      continue 2
    fi
  done

  # 1. Pinned commit in the parent repo's index
  pinned=$(git submodule status "$path" 2>/dev/null \
           | awk '{print $1}' | tr -d '+-U') || true

  if [[ -z "$pinned" ]]; then
    echo "pull-submodules: '$path' listed in .gitmodules but not initialised, skipping." >&2
    continue
  fi

  # 2. Remote URL for this submodule
  # Resolve relative URLs against the parent remote's base
  raw_url=$(git config --file .gitmodules \
            "submodule.${path}.url" 2>/dev/null) || true

  if [[ -z "$raw_url" ]]; then
    echo "pull-submodules: could not read remote URL for '$path', skipping." >&2
    continue
  fi

  # Expand "../sibling" relative URLs using the parent's origin URL
  if [[ "$raw_url" == ../* ]]; then
    parent_remote=$(git remote get-url origin 2>/dev/null) || true
    if [[ -n "$parent_remote" ]]; then
      parent_base="${parent_remote%/*}"
      raw_url="${parent_base}/${raw_url#../}"
    fi
  fi

  # 3. Fetch remote HEAD (network call — fail silently if offline or auth fails)
  remote_sha=$(git ls-remote "$raw_url" "$REMOTE_BRANCH" 2>/dev/null \
               | awk '{print $1}') || true

  if [[ -z "$remote_sha" ]]; then
    continue  # Unreachable remote — do not block or warn
  fi

  # 4. Compare — up to date, nothing to do
  if [[ "$pinned" == "$remote_sha" ]]; then
    continue
  fi

  # 5. Stale — auto-update if this is the designated submodule, otherwise warn
  if [[ "$path" == "$AUTO_UPDATE" ]]; then
    echo "pull-submodules: '$path' is behind remote — auto-updating and staging." >&2
    if git submodule update --remote "$path" 2>/dev/null; then
      git add "$path"
      echo "pull-submodules: '$path' updated to $(git submodule status "$path" | awk '{print $1}' | tr -d '+-U') and staged." >&2
    else
      echo "pull-submodules: WARNING — auto-update of '$path' failed; please update manually." >&2
      warned=1
    fi
  else
    echo "" >&2
    echo "WARNING: submodule '$path' is behind the remote." >&2
    echo "  Pinned : $pinned" >&2
    echo "  Remote : $remote_sha" >&2
    echo "  To update: git submodule update --remote $path" >&2
    echo "" >&2
    warned=1
  fi

done

# Summary line if any non-auto submodule was stale
if [[ $warned -eq 1 ]]; then
  echo "pull-submodules: one or more submodules are out of date." \
       "Run 'git submodule update --remote' to update all." >&2
fi

exit 0
