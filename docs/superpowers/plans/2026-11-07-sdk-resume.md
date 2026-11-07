# Resumable SDK Downloads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retain SDK download progress across interrupted/slow requests and verify a new main package build.

**Architecture:** Leave metadata buffering intact. Add an archive-only HTTP/1.1 resume loop over the hash-scoped `.part` file with an overall deadline shared by snapshot refreshes.

**Tech Stack:** Bash, curl, Python HTTP fixtures, GnuPG, GitHub CLI.

**Spec:** `docs/superpowers/specs/2026-11-07-sdk-resume-design.md`.

## Global Constraints

- Archive requests: 1800 seconds; shared download deadline: 3600 seconds;
  at most 12 requests per metadata round; all configurable as positive integers.
- Preserve signature/SHA-256 verification, metadata buffering, package selection
  and the README IP correction. Reuse the current checkout.
- User authorized commit/push and `Build-Packages` on `master` with
  `sdk_version=main`, `arch=ALL`, `package=ALL`; monitor until completion.

## Review Focus

- Partial transfers must advance Range offsets and survive transport failures.
- Servers ignoring Range or returning 416 must not cause duplicate bytes.
- Completed/resumed archives must match the trusted hash; corruption is removed.
- Unchanged metadata retains progress; changed metadata cannot reuse old bytes.
- Timeout/retry/refresh loops must share a finite budget and preserve metadata behavior.

### Task 1: Implement and publish SDK resumption

**Files:** `scripts/SDK-script.sh`, `tests/SDK-script-download.test.sh`, new `tests/SDK-script-resume.test.sh`, `README.md`.

**Interfaces:** `download_sdk_archive(url, partial_path)` returns transfer success/failure; the caller alone promotes a SHA-256-verified partial file. Settings: `SDK_DOWNLOAD_TIMEOUT=3600`, `SDK_DOWNLOAD_REQUEST_TIMEOUT=1800`, `SDK_DOWNLOAD_RETRY_COUNT=12`. `download_sdk_with_metadata_retry` shares a deadline across rounds.

- [x] Add real-curl loopback regressions for dropped/slow bodies, Range ignored,
  416, corruption, saved progress, and budget exhaustion; observe failures first.
- [x] Implement archive resumption, hash-scoped checkpoints, shared deadline,
  clean Range fallback and diagnostics. Update the existing transport fixtures.
- [x] Run every shell test, Bash syntax checks and `git diff --check`; perform
  independent review and fix material findings with a failing regression first.
- [ ] Commit/push, dispatch only main for both architectures, verify the new
  run uses the new commit, and monitor builds and publication until finished.

## Local Verification

- All eight shell test scripts, Bash syntax checks and `git diff --check` pass.
- Thirteen real-curl scenarios cover interrupted/slow transfers, Range ignored
  and 416, complete/incomplete checkpoints, corruption, shared request and
  refresh budgets, and metadata backoff. Real GnuPG signatures verify unchanged
  metadata retains progress and a new hash discards the old checkpoint.
- The old downloader failed the new resumption cases. The deadline/backoff
  regressions failed before their fixes and pass afterward.
- Independent review found no Critical or Important issues; its small backoff
  overrun was fixed and the documented cache identity clarified.
- A live official SDK range request returned HTTP 206 and exactly 65,536 bytes
  for range 65536–131071, confirming support for resumption.
