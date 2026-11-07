# SDK Download Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover SDK downloads from HTTP/2 failures while retaining verified metadata and archive integrity.

**Architecture:** Share a buffered curl download helper across the five SDK HTTP request sites. Keep SDK selection, verification and build behavior unchanged.

**Tech Stack:** Bash, curl, Python, GnuPG.

**Spec:** `docs/superpowers/specs/2026-11-07-sdk-download-design.md`.

## Global Constraints

- Metadata: 120 seconds per attempt. SDK archives: 900 seconds per attempt.
- Stall detection: below 1024 bytes/s for 60 seconds.
- Preserve signature and SHA-256 checks, snapshot refresh and the README IP correction.
- Work in the current checkout. Subsequent user authorization covers commit
  and push to `origin/master`, then `Build-Packages` with `sdk_version=main`,
  `arch=ALL`, `package=ALL`.

## Review Focus

- A partial first response must not contaminate successful fallback output.
- Successful first requests must not require fallback.
- Failed or corrupt fallback data must never become a cached SDK archive.
- All metadata paths must share recovery behavior, including signed manifests.
- Local SDK files and existing verified archives must retain their behavior.

### Task 1: Repair SDK HTTP downloads

**Files:** `scripts/SDK-script.sh`, `tests/SDK-script-download.test.sh`, `tests/SDK-script-metadata.test.sh`, `tests/Roc-script-feeds.test.sh`, `README.md`.

**Interfaces:** Add `download_http_file(url, output="-", max_time=120)`, returning zero only after a complete transfer. Use it from SDK discovery, version discovery, checksum/signature fetch and archive download.

- [x] Add transport-failure fixtures and run the new regression; observe missing recovery/timeouts before implementation.
- [x] Implement the helper: one normally negotiated request, then HTTP/1.1 with two retries, `--retry-all-errors`, and a retry time limit equal to `max_time`; buffer both attempts and clean up on failure.
- [x] Route all five requests through it; use 900 seconds for archives and a neutral snapshot-refresh message. Document the behavior in README.
- [x] Exercise signed metadata recovery with real GnuPG verification. Run every `tests/*.test.sh`, Bash syntax checks and `git diff --check`; inspect the complete diff and request independent review.

## Verification Record

- All seven `tests/*.test.sh` scripts pass with GNU Bash, awk, sed, coreutils and GnuPG.
- Eight download regressions cover protocol recovery, timeout/retry options,
  cached/local SDKs, corruption, partial responses and empty HTTP 304 fallback.
- The two added signed-metadata regressions fail against the original SDK
  script and pass with the repair; signature verification uses real GnuPG.
- Independent review reproduced partial-response reuse on HTTP 304. The
  new regression failed before explicit truncation and passed afterward.
- Real curl against a loopback HTTP server recovers from a truncated response
  to HTTP 200 and rejects truncated JSON followed by HTTP 304.
- Mutation checks detect reduced archive timeouts, removed retry-all-errors
  and changed stall thresholds. All shell syntax checks, eight workflow YAML
  parses and `git diff --check` pass.
- An existing integration test directly executed a script tracked as mode
  100644; it now invokes Bash explicitly, and the full suite passes.
- Local verification did not include a full SDK/package compilation. The user
  subsequently authorized publishing the repair and starting a new `main`
  package build for both architectures from the new commit.
