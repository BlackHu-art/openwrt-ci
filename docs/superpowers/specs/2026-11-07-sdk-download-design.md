# SDK Download Recovery

## Intent

Repair the user-reported Actions run 42306898331. Both `main` SDK jobs
failed before compilation because HTTP/2 transfers repeatedly ended with
curl exit 92; signed manifests were verified successfully.

## Approach

Use a shared `download_http_file(url, output, max_time)` helper for SDK
archives and metadata. Try normal protocol negotiation once, then retry
using HTTP/1.1. This preserves the working first request and recovers from
the observed failure without relying on runner or upstream changes.
Forcing HTTP/1.1 immediately would also avoid HTTP/2, but would change every
successful first request. Increasing the existing retry count alone would
repeat the failing protocol.

## Requirements

- Metadata transfers have a 120-second per-attempt limit; SDK archives
  have a 900-second per-attempt limit. Abort transfers below 1024 bytes/s
  for 60 seconds. Bound HTTP/1.1 retries by the transfer's time limit.
- Buffer responses in temporary files so failed requests never emit partial
  metadata. Clean up failed downloads; publish SDK archives only after SHA-256
  verification. Preserve existing signature verification and snapshot refresh.
- Describe snapshot retry as download or verification failure, without
  asserting that upstream SDK contents changed.
- Preserve the README IP correction. After local verification, the user
  authorized committing and pushing the repair to `origin/master`, then
  dispatching `Build-Packages` with `sdk_version=main`, `arch=ALL`,
  `package=ALL` to build only the two requested snapshot architectures.
