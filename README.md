# spyre-pre-commit-hooks

A shared [pre-commit](https://pre-commit.com/) hook repository that provides automated checks for projects using Git submodules. Hooks run on every `git commit` to surface common issues before they reach CI.

---

## Hooks

### `pull-submodules`

Checks every submodule declared in `.gitmodules` and **blocks the commit** if the designated submodule is pinned to a commit that is behind the remote HEAD.

**Problem it solves:** Submodules are pinned to a specific commit in the parent repo's index. When the submodule moves forward — new features, bug fixes, or breaking changes — the parent repo silently falls behind. Without a local check, stale submodule pointers only surface as confusing build or runtime failures in CI, which can take significant time to diagnose and trace back to a version mismatch.

**What it does:**

- Reads all submodule paths from `.gitmodules` automatically — no configuration needed when submodules are added
- Reads the pinned SHA directly from the git staging index (`git ls-files --stage`)
- Calls `git ls-remote` against the submodule's remote to get the current HEAD SHA — read-only, no working tree writes, works even if the submodule is not initialised locally
- If the designated submodule is stale: **exits 1**, prints the pinned SHA, remote SHA, and the exact fix command
- All other stale submodules: prints a warning but **does not block** the commit
- Offline-safe: if the remote is unreachable the hook passes silently rather than blocking the commit

**Example output when a submodule is stale:**

```
pull-submodules..........................................................Failed
- hook id: pull-submodules
- exit code: 1

pull-submodules: 'test_submodule' is out of date.
  Pinned : <example hash 1>
  Remote : <example hash 2>
  Fix    : git submodule update --remote test_submodule && git add test_submodule
```

**To fix:** run the printed command, then re-commit:

```bash
git submodule update --remote test_submodule && git add test_submodule
git commit -m "your message"
```

**Environment variable overrides:**

| Variable | Default | Purpose |
|---|---|---|
| `AUTO_UPDATE_SUBMODULE` | `test_submodule` | Submodule path that blocks commits when stale |
| `SUBMODULE_REMOTE_BRANCH` | `HEAD` | Remote ref to compare against |
| `SUBMODULE_SKIP` | *(empty)* | Space-separated list of submodule paths to skip entirely |

---

### `check-main`

Performs an **in-memory merge test** against `origin/main` and blocks the commit if conflicts are detected.

**Problem it solves:** Merge conflicts with `main` are easier to resolve when caught early — while the context is fresh and the diff is small. Without a local check, conflicts only surface during PR review or CI, requiring a context switch back to a branch that may be days old.

**What it does:**

- Fetches `origin/main` silently
- Uses `git merge-tree --write-tree` to test the merge in memory — no working tree modifications, no side effects
- If conflicts exist: **exits 1** and prints the conflicting files
- If no conflicts: passes silently

**Example output when a conflict is detected:**

```
check-main...............................................................Failed
- hook id: check-main
- exit code: 1

================ Merge Conflict ================
This branch conflicts with origin/main:

CONFLICT (content): Merge conflict in src/some_file.cpp

Please merge/rebase and resolve conflicts before committing.
================================================
```

**To fix:** rebase or merge `main` into your branch, resolve conflicts, then re-commit:

```bash
git fetch origin
git rebase origin/main
# resolve any conflicts
git commit -m "your message"
```

---

## Usage

Add the following to your project's `.pre-commit-config.yaml`:

```yaml
- repo: https://github.com/<org>/Spyre-Pre-Commit-Hooks
  rev: <tag-or-sha>
  hooks:
  - id: pull-submodules
  - id: check-main
```

Then install pre-commit and the hooks:

```bash
pip install pre-commit
pre-commit install
```

Both hooks will run automatically on every `git commit`. To run them manually against all files:

```bash
pre-commit run --all-files
```

---

## Requirements

- [pre-commit](https://pre-commit.com/) >= 2.0
- bash >= 3.2
- git >= 2.38 (required by `check-main` for `git merge-tree --write-tree`)
- Network access to submodule remotes (for `pull-submodules`; degrades silently if offline)
