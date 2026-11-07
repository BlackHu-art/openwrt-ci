# Resumable SDK Downloads

## Evidence and goal

Run 42334399411 attempt 2 exhausted all three SDK download rounds on aarch64.
HTTP/1.1 transfers were interrupted or hit 900 seconds after receiving only
109–161 MB of the 267 MB archive. Each retry discarded the bytes already
received. x86-64 separately lost its hosted runner.

The user authorized repairing the timeout, committing and pushing the change,
starting new `main` package builds for x86-64 and aarch64, and monitoring them
to completion.

## Approach and constraints

- Keep the existing buffered metadata downloader and signature verification.
  Use a separate archive downloader, starting with HTTP/1.1 and recomputing
  curl's resume offset from the current `.part` file on every attempt.
- Use 1800 seconds per archive request, 3600 seconds shared across archive
  retries and snapshot metadata refreshes, and at most 12 transfer attempts
  per metadata round. Expose these as positive-integer SDK download settings.
  Keep the 20-second connection and 60-second low-speed protections.
- Retain incomplete bytes for the same archive name and signed hash; discard corrupt bytes and
  bytes belonging to superseded metadata. Accept only the final exact SHA-256.
  If a server ignores or rejects Range, restart cleanly without appending a
  full response to a partial file.
- Merely raising the timeout would still waste progress on disconnects.
  Reusing the metadata downloader would compromise its partial-response
  isolation. Keep these two paths separate.
- Preserve all package selections and the README IP correction. Publish to
  `origin/master`, dispatch `Build-Packages` with `main/ALL/ALL`, and follow
  that new run until completion. Do not rerun unrelated builds.
