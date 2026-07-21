#!/usr/bin/env bash
# check_submodules.sh
#
# Iterates over every submodule declared in .gitmodules and warns when
# any of them is pinned to a commit that is behind the remote HEAD.
#
# Always exits 0 — this is a warning-only hook; it never blocks a commit.
#
# Optional env vars
#   SUBMODULE_REMOTE_BRANCH   Remote ref to compare against (default: HEAD)
#   SUBMODULE_SKIP            Space-separated list of submodule paths to skip

set -euo pipefail

REMOTE_BRANCH="${SUBMODULE_REMOTE_BRANCH:-HEAD}"
SKIP_LIST="${SUBMODULE_SKIP:-}"

# ── Collect all submodule paths from .gitmodules ─────────────────────────────
if [[ ! -f .gitmodules ]]; then
  exit 0  # No submodules in this repo — nothing to do
fi

mapfile -t submodule_paths < <(
  git config --file .gitmodules --get-regexp '\.path$' \
  | awk '{print $2}'
)

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

  # 4. Compare
  if [[ "$pinned" != "$remote_sha" ]]; then
    echo "" >&2
    echo "WARNING: submodule '$path' is behind the remote." >&2
    echo "  Pinned : $pinned" >&2
    echo "  Remote : $remote_sha" >&2
    echo "  To update: git submodule update --remote $path" >&2
    echo "" >&2
    warned=1
  fi

done

# Summary line if any submodule was stale
if [[ $warned -eq 1 ]]; then
  echo "pull-submodules: one or more submodules are out of date." \
       "Run 'git submodule update --remote' to update all." >&2
fi

exit 0
