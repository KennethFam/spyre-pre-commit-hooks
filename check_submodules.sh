#!/usr/bin/env bash
# check_submodules.sh
#
# For every submodule declared in .gitmodules:
#   - Stale submodules print a warning only (exit 0).
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

submodule_paths=()
while IFS= read -r line; do
  submodule_paths+=("$line")
done < <(git config --file .gitmodules --get-regexp '\.path$' | awk '{print $2}')

if [[ ${#submodule_paths[@]} -eq 0 ]]; then
  exit 0
fi

# ── Check each submodule ──────────────────────────────────────────────────────
for path in "${submodule_paths[@]}"; do

  # Honour the skip list
  for skip in $SKIP_LIST; do
    if [[ "$path" == "$skip" ]]; then
      continue 2
    fi
  done

  # 1. Pinned commit from the staging index (what will actually be committed).
  #    git ls-files --stage reads the index directly, avoiding the working-tree
  #    confusion that `git submodule status` has with the +/-/U prefix.
  pinned=$(git ls-files --stage -- "$path" 2>/dev/null \
           | awk '{print $2}') || true

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

  # 5. Stale — block the commit and tell the developer exactly what to run.
  #    We do not attempt to auto-stage here because pre-commit's stash/restore
  #    mechanism always overwrites index changes made inside a hook, causing an
  #    infinite loop. The developer runs the fix outside pre-commit's stash
  #    window, then re-commits cleanly.
  if [[ "$pinned" != "$remote_sha" ]]; then
    echo ""
    echo "============================ WARNING ============================"
    echo "pull-submodules: '$path' is out of date."
    echo "  Pinned : $pinned"
    echo "  Remote : $remote_sha"
    echo "  Fix    : git submodule update --remote $path && git add $path"
    echo "================================================================="
    echo ""
done

exit 0