# Remove Aria2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Aria2, AriaNg, and LuCI Aria2 from every supported firmware and standalone SDK package build path.

**Architecture:** Remove selection at the configuration boundary, then remove the now-dead custom feed, compilation, artifact, workflow, and documentation paths. Preserve the upstream feed directories in `Roc-script.sh` so unrelated feed behavior is not changed destructively.

**Tech Stack:** Bash, OpenWrt Kconfig fragments, GitHub Actions YAML, Markdown

## Global Constraints

- No supported build path may select, replace, compile, publish, or advertise `aria2`, `ariang`, or `luci-app-aria2`.
- Other package selections and custom feed replacements must remain unchanged.
- Old Aria2 standalone-package selections must be rejected rather than silently mapped to another package.

---

### Task 1: Preserve Built-in Aria2 Feeds in Roc Script

**Files:**
- Modify: `tests/Roc-script-feeds.test.sh`
- Modify: `scripts/Roc-script.sh:42-80`

**Interfaces:**
- Consumes: the existing fake-Git integration harness in `tests/Roc-script-feeds.test.sh`
- Produces: `Roc-script.sh` behavior that leaves built-in `feeds/packages/net/aria2` and `feeds/packages/net/ariang` untouched

- [ ] **Step 1: Change the integration test to require preservation**

Create sentinel files before running the script:

```bash
printf 'built-in aria2\n' > "$openwrt_root/feeds/packages/net/aria2/.built-in"
printf 'built-in ariang\n' > "$openwrt_root/feeds/packages/net/ariang/.built-in"
```

Replace the directory-only assertion with:

```bash
for package_name in aria2 ariang; do
  if [[ ! -f "$openwrt_root/feeds/packages/net/$package_name/.built-in" ]]; then
    printf 'Roc-script.sh did not preserve feeds/packages/net/%s\n' "$package_name" >&2
    exit 1
  fi
done
```

- [ ] **Step 2: Run the test and verify the current replacement behavior fails**

Run:

```bash
"C:/Program Files/Git/bin/bash.exe" tests/Roc-script-feeds.test.sh
```

Expected: FAIL with `Roc-script.sh did not preserve feeds/packages/net/aria2` because the current script deletes and recreates the directory.

- [ ] **Step 3: Remove Aria2 replacement behavior from Roc script**

Delete these lines from `scripts/Roc-script.sh`:

```bash
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/aria2
git_sparse_clone aria2 https://github.com/laipeng668/packages net/aria2
mv -f package/aria2 feeds/packages/net/aria2
git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang
mv -f package/ariang feeds/packages/net/ariang
```

Remove `Aria2 &` from the nearby package-list comment.

- [ ] **Step 4: Run the integration test and syntax check**

Run:

```bash
"C:/Program Files/Git/bin/bash.exe" tests/Roc-script-feeds.test.sh
"C:/Program Files/Git/bin/bash.exe" -n scripts/Roc-script.sh
"C:/Program Files/Git/bin/bash.exe" -n tests/Roc-script-feeds.test.sh
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit the Roc behavior change**

```bash
git add scripts/Roc-script.sh tests/Roc-script-feeds.test.sh
git commit -m "fix: stop replacing Aria2 feeds"
```

### Task 2: Remove Aria2 from Standalone SDK Builds

**Files:**
- Create: `tests/SDK-script-package-selection.test.sh`
- Modify: `scripts/SDK-script.sh:43-79,311-330,442-459,550-559,694-749`
- Modify: `.github/workflows/Build-Packages.yml:31-39`

**Interfaces:**
- Consumes: `normalize_package_selection(selection)` from the sourceable SDK script
- Produces: an SDK package selector that rejects `aria2`, `ariang`, and `luci-app-aria2`

- [ ] **Step 1: Write a failing package-selection test**

Create `tests/SDK-script-package-selection.test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/SDK-script.sh"

for selection in aria2 ariang luci-app-aria2; do
  if (normalize_package_selection "$selection" >/dev/null 2>&1); then
    printf 'Removed package selection is still accepted: %s\n' "$selection" >&2
    exit 1
  fi
done
```

- [ ] **Step 2: Run the selector test and verify it fails**

Run:

```bash
"C:/Program Files/Git/bin/bash.exe" tests/SDK-script-package-selection.test.sh
```

Expected: FAIL with `Removed package selection is still accepted: aria2`.

- [ ] **Step 3: Remove SDK Aria2 paths**

In `scripts/SDK-script.sh`:

- Remove `luci-app-aria2` from the supported selection case.
- Remove the `aria2 | ariang` compatibility-alias case.
- Remove Aria2 names from the unsupported-selection error text.
- Stop deleting and custom-cloning `feeds/packages/net/aria2` and `feeds/packages/net/ariang`.
- Delete the Aria2 artifact-filter blocks.
- Delete the Aria2 artifact-group branch.
- Delete the Aria2, AriaNg, and LuCI Aria2 compile-target blocks.

In `.github/workflows/Build-Packages.yml`, delete:

```yaml
          - luci-app-aria2
```

- [ ] **Step 4: Run selector, Bash syntax, and residual-reference checks**

Run:

```bash
"C:/Program Files/Git/bin/bash.exe" tests/SDK-script-package-selection.test.sh
"C:/Program Files/Git/bin/bash.exe" -n scripts/SDK-script.sh
"C:/Program Files/Git/bin/bash.exe" -n tests/SDK-script-package-selection.test.sh
rg -n -i "aria2|ariang" scripts/SDK-script.sh .github/workflows/Build-Packages.yml
```

Expected: the three Bash commands exit 0; `rg` exits 1 with no matches.

- [ ] **Step 5: Commit standalone SDK removal**

```bash
git add scripts/SDK-script.sh tests/SDK-script-package-selection.test.sh .github/workflows/Build-Packages.yml
git commit -m "build: remove Aria2 package target"
```

### Task 3: Remove Firmware Configuration and Documentation

**Files:**
- Modify: `configs/JDCloud.config:17-33`
- Modify: `configs/x86-64.config:18-34`
- Modify: `configs/Packages.config:11,19-35`
- Modify: `README.md:31-38`

**Interfaces:**
- Consumes: OpenWrt `make defconfig` configuration fragments
- Produces: firmware configurations with no Aria2 packages or feature flags

- [ ] **Step 1: Remove firmware selections**

Delete the complete `### Aria2配置项 ###` sections from all three configuration files, and delete the standalone `CONFIG_PACKAGE_luci-app-aria2=y` line from `configs/Packages.config`.

- [ ] **Step 2: Update standalone-package documentation**

Remove `luci-app-aria2` and its legacy aliases from the package-choice paragraph, remove `aria2` and `ariang` from the configuration examples, and delete the two Aria2 source bullets. Preserve the descriptions of all remaining packages.

- [ ] **Step 3: Verify supported surfaces contain no Aria2 references**

Run:

```bash
rg -n -i "aria2|ariang" configs scripts .github/workflows README.md
```

Expected: only test assertions that the removed selections are rejected or built-in feeds are preserved; no build configuration, production script, workflow, or README matches.

- [ ] **Step 4: Commit configuration and documentation removal**

```bash
git add configs/JDCloud.config configs/x86-64.config configs/Packages.config README.md
git commit -m "config: remove Aria2 from firmware builds"
```

### Task 4: Final Verification

**Files:**
- Verify: all files changed by Tasks 1-3

**Interfaces:**
- Consumes: completed Aria2 removal
- Produces: evidence that syntax, regression behavior, and repository scope meet the design

- [ ] **Step 1: Run all shell tests and syntax checks**

```bash
"C:/Program Files/Git/bin/bash.exe" tests/Roc-script-feeds.test.sh
"C:/Program Files/Git/bin/bash.exe" tests/SDK-script-package-selection.test.sh
"C:/Program Files/Git/bin/bash.exe" -n scripts/Roc-script.sh
"C:/Program Files/Git/bin/bash.exe" -n scripts/SDK-script.sh
"C:/Program Files/Git/bin/bash.exe" -n tests/Roc-script-feeds.test.sh
"C:/Program Files/Git/bin/bash.exe" -n tests/SDK-script-package-selection.test.sh
```

Expected: all commands exit 0.

- [ ] **Step 2: Validate YAML when PyYAML is installed**

```bash
python -c "import pathlib, yaml; yaml.safe_load(pathlib.Path('.github/workflows/Build-Packages.yml').read_text(encoding='utf-8'))"
```

Expected: exit 0. If PyYAML is unavailable, report the skipped parser check and rely on the one-line list deletion plus diff inspection.

- [ ] **Step 3: Run whitespace and scope checks**

```bash
git diff --check HEAD~3..HEAD
git status --short --branch
git log -4 --oneline
```

Expected: no whitespace errors; only intentional commits and no uncommitted implementation changes.
