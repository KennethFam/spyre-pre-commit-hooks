#!/bin/bash

git fetch origin main 2>/dev/null

# Attempt a dry-run merge with origin/main; if it would conflict, print a warning
if ! git merge --no-commit --no-ff origin/main 2>/dev/null; then
    echo "WARNING: Your branch has conflicts with origin/main."
fi

# Always abort to leave the working tree clean
git merge --abort 2>/dev/null

exit 0
