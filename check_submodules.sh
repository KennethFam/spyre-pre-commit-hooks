#!/usr/bin/env bash
# check_submodules.sh
#
# For every submodule declared in .gitmodules:
#   - If the submodule is stale: prints a warning suggesting an update.
#     The commit is NOT blocked — the warning is advisory only.
#
# Optional env vars
#   SUBMODULE_REMOTE_BRANCH   Remote ref to compare against (default: HEAD)
#   SUBMODULE_SKIP            Space-separated list of submodule paths to skip
#   AUTO_UPDATE_SUBMODULE     Submodule path to highlight in warnings (default: common)

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

  # 5. Stale — warn the developer but do not block the commit.
  echo ""
  echo "WARNING: submodule '$path' is behind the remote."
  echo "  Pinned : $pinned"
  echo "  Remote : $remote_sha"
  echo "  To update: git submodule update --remote $path && git add $path"
  echo ""

done

exit 0