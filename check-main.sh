#!/bin/sh

# pre-commit sets GIT_DIR; derive the worktree root from it
REPO_ROOT=$(git rev-parse --show-toplevel)

# Target branch to check conflicts against
TARGET_BRANCH="origin/main"

# Silently fetch latest main
git -C "$REPO_ROOT" fetch origin main >/dev/null 2>&1

# Perform an in-memory merge test against HEAD
CONFLICT_OUTPUT=$(git -C "$REPO_ROOT" merge-tree --write-tree HEAD "$TARGET_BRANCH" 2>&1 | grep -i "CONFLICT")

if [ -n "$CONFLICT_OUTPUT" ]; then
    echo ""
    echo "================ Merge Conflict ================"
    echo "This branch conflicts with $TARGET_BRANCH:"
    echo ""
    echo "$CONFLICT_OUTPUT"
    echo ""
    echo "Please merge/rebase and resolve conflicts before committing."
    echo "================================================"
    echo ""
    exit 1
fi

exit 0
