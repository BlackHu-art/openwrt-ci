# Sync Upstream Package Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the missing Go and frp fixes from `laipeng668/openwrt-ci-roc` to both build paths.

**Architecture:** Adapt the two upstream patches to the existing scripts. Exercise real sparse clones against local Git fixtures, then run the existing regression suite.

**Tech Stack:** Bash, Git, GitHub Actions.

**Spec:** Upstream commits [03558f8](https://github.com/laipeng668/openwrt-ci-roc/commit/03558f85e63daf119aafdde3c2101d0c50a8432c) and [43e54af](https://github.com/laipeng668/openwrt-ci-roc/commit/43e54af3a76b28c0f79a094d0ae5e3341664221a), plus the user's confirmed scope below.

## Global Constraints

- Keep the existing 6.12 kernel; do not apply upstream's testing-kernel update.
- Preserve Aria2 removal, default IP, local package additions, banner and Release fixes.
- Commit and push only after explicit user authorization; do not trigger builds.

## Review Focus

- Firmware configurations without frp must still receive the updated Go package.
- SDK selections without frp must still receive the updated Go package.
- A firmware build selecting only one frp LuCI app must not require the other app's Makefile.
- Both frp LuCI apps must retain their normal package dependencies after removing version constraints.
- Source revision records must continue to reflect the actual Go checkout.

### Task 1: Sync Go refresh behavior

**Files:** `scripts/Roc-script.sh`, `scripts/SDK-script.sh`, `tests/upstream-package-fixes.test.sh`, `tests/Roc-script-feeds.test.sh`, `README.md`.

**Interfaces:** Existing firmware config arguments and SDK `PACKAGE_SELECTION`; updated `feeds/packages/lang/golang` and source revision records.

- [x] Add local Git fixtures and tests for firmware without frp and SDK selections `nginx` and `luci-app-lucky`; assert the new Go Makefile replaces the old one and its checkout is recorded.
- [x] Run `bash tests/upstream-package-fixes.test.sh go`; expect failure because non-frp builds retain the old Go package.
- [x] Move Go removal and cloning outside the frp selection guards in both scripts, following `03558f8`; adapt the existing firmware test's Git fixture to support revision recording.
- [x] Repeat the test; expect exit 0, then run the existing tests.

### Task 2: Sync frp dependency compatibility

**Files:** `scripts/Roc-script.sh`, `scripts/SDK-script.sh`, `tests/upstream-package-fixes.test.sh`.

**Interfaces:** Downloaded frp LuCI Makefiles; remove `LUCI_EXTRA_DEPENDS:=` while retaining `LUCI_DEPENDS`.

- [x] Test firmware client-only, server-only and combined selections, and SDK `luci-app-frpc`, `luci-app-frps` and `frp`; assert version constraints are removed and regular dependencies remain.
- [x] Run `bash tests/upstream-package-fixes.test.sh frp`; expect failure on the retained version constraint.
- [x] Apply the Makefile cleanup from `43e54af` after each relevant checkout.
- [x] Run all `tests/*.test.sh`, Bash syntax checks, workflow YAML parsing and `git diff --check`; expect exit 0. Inspect the final diff for scope and local customizations.

## Verification Record

- Before the changes, both firmware and SDK cases independently failed on the old Go package and retained frp version constraints (using the optional `firmware` / `sdk` test-path filter).
- After the changes, all four test scripts passed, including nine new local-Git integration scenarios.
- Git Bash syntax checks, parsing all eight workflow YAML files and `git diff --check` passed.
- Independent read-only review found no issues in the scoped update.
- No complete firmware or SDK compilation, real upstream package checkout, Release upload or device test was performed.
