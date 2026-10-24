#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
source "$repo_root/scripts/SDK-script.sh"

OPENWRT_DOWNLOADS_BASE_URL=https://downloads.example.invalid
OPENWRT_SDK_BASE_URL=""
SDK_URL=""
OPENWRT_TARGET=x86
OPENWRT_SUBTARGET=64
request_log="$test_root/requests"
versions='{"stable_version":"25.12.6","oldstable_version":"24.10.8","upcoming_version":"","versions_list":["24.10.9-rc1","24.10.8","23.05.6","24.10.10","24.10.2","25.12.6"]}'
archive_name=openwrt-sdk-24.10.10-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst
fixture_manifest="$(printf '%064d *%s\n%064d *%s\n' 1 openwrt-imagebuilder-example.tar.zst 2 "$archive_name")"
fetch_failure=false

# Only the network boundary is replaced. Directory indexes reproduce the
# upstream HTTP 502; the actual JSON, manifest and URL parsing runs unchanged.
curl() {
  local url="" output=/dev/stdout
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o) output="$2"; shift 2 ;;
      --retry | --connect-timeout | --max-time) shift 2 ;;
      -*) shift ;;
      *) url="$1"; shift ;;
    esac
  done
  printf '%s\n' "$url" >> "$request_log"
  if [ "$fetch_failure" = true ]; then
    printf 'curl: (22) The requested URL returned error: 502\n' >&2
    return 22
  fi
  {
    case "$url" in
      "$OPENWRT_DOWNLOADS_BASE_URL/.versions.json") printf '%s\n' "$versions" ;;
      "$OPENWRT_DOWNLOADS_BASE_URL"/*/sha256sums) printf '%s\n' "$fixture_manifest" ;;
      "$OPENWRT_DOWNLOADS_BASE_URL"/*/sha256sums.asc) cat "$test_root/sha256sums.asc" ;;
      *) printf 'curl: (22) Directory index returned HTTP 502: %s\n' "$url" >&2; return 22 ;;
    esac
  } > "$output"
}

fail() { printf '%s\n' "$*" >&2; return 1; }

latest_release_uses_json() {
  [ "$(resolve_latest_release_version 24.10)" = 24.10.10 ] ||
    fail 'Stable series must select the numerically latest final release from official JSON'
}

stable_sdk_uses_manifest() {
  OPENWRT_SDK_VERSION=24.10
  [ "$(resolve_sdk_url)" = "$OPENWRT_DOWNLOADS_BASE_URL/releases/24.10.10/targets/x86/64/$archive_name" ] ||
    fail 'SDK discovery must work while HTML directory indexes return 502'
}

snapshot_sdk_uses_manifest() {
  OPENWRT_SDK_VERSION=main
  [ "$(resolve_sdk_url)" = "$OPENWRT_DOWNLOADS_BASE_URL/snapshots/targets/x86/64/$archive_name" ] ||
    fail 'Snapshot SDK discovery must use the direct manifest'
}

archive_formats_are_supported() {
  OPENWRT_SDK_VERSION=main
  local extension
  for extension in xz zst gz; do
    archive_name="openwrt-sdk-example.Linux-x86_64.tar.$extension"
    fixture_manifest="$(printf '%064d  %s\n' 2 "$archive_name")"
    [ "$(resolve_sdk_url)" = "$OPENWRT_DOWNLOADS_BASE_URL/snapshots/targets/x86/64/$archive_name" ] || return 1
  done
}

release_failure_stops_resolution() {
  OPENWRT_SDK_VERSION=24.10
  fetch_failure=true
  local result
  if result="$(resolve_sdk_url 2> "$test_root/error")"; then
    fail 'Failed release metadata fetch must return a failure'; return 1
  fi
  [ -z "$result" ] || fail 'Failed release lookup emitted a malformed SDK URL'
  if grep -Fq '/releases//' "$request_log"; then
    fail 'Failed release lookup must not request releases//targets'; return 1
  fi
}

missing_series_stops_resolution() {
  OPENWRT_SDK_VERSION=23.05
  versions='{"versions_list":["24.10.8","23.05.7-rc1"]}'
  local result
  if result="$(resolve_sdk_base_url 2> "$test_root/error")"; then
    fail 'A missing final release must fail instead of emitting releases//targets'; return 1
  fi
  [ -z "$result" ] || fail 'Missing series emitted a malformed base URL'
}

malformed_json_is_rejected() {
  OPENWRT_SDK_VERSION=24.10
  versions='{"versions_list": "24.10.10"}'
  local result
  if result="$(resolve_sdk_base_url 2> "$test_root/error")"; then
    fail 'Invalid versions_list type must fail'; return 1
  fi
  [ -z "$result" ] || fail 'Malformed metadata emitted a base URL'
}

missing_sdk_is_rejected() {
  OPENWRT_SDK_VERSION=main
  fixture_manifest="$(printf '%064d *%s\n' 1 packages/openwrt-sdk-not-an-archive.tar.zst)"
  local result
  if result="$(resolve_sdk_url 2> "$test_root/error")"; then
    fail 'A nested path must not be accepted as the SDK archive'; return 1
  fi
}

failed_manifest_is_rejected() {
  OPENWRT_SDK_VERSION=main
  fetch_failure=true
  local result
  if result="$(resolve_sdk_url 2> "$test_root/error")"; then
    fail 'Failed manifest download must fail SDK resolution'; return 1
  fi
}

# Exercise the unchanged trust boundary with a real detached signature and key.
# No gpg/gpgv or checksum implementation is mocked.
RUNNER_TEMP="$test_root"
key_home="$test_root/key-home"
mkdir "$key_home"
chmod 700 "$key_home"
gpg --homedir "$key_home" --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'SDK Metadata Test <sdk@example.invalid>' ed25519 sign 0 > /dev/null 2>&1
OPENWRT_SIGNING_KEY="$test_root/key.asc"
gpg --homedir "$key_home" --batch --armor --export > "$OPENWRT_SIGNING_KEY"
OPENWRT_SIGNING_KEY_FINGERPRINT="$(
  gpg --homedir "$key_home" --batch --with-colons --list-keys 2>/dev/null |
    awk -F: '$1 == "fpr" {print $10; exit}'
)"
printf '%s\n' "$fixture_manifest" > "$test_root/sha256sums"
gpg --homedir "$key_home" --batch --pinentry-mode loopback --passphrase '' \
  --armor --detach-sign "$test_root/sha256sums"

signed_metadata_is_verified() {
  OPENWRT_SDK_VERSION=main
  SDK_SHA256=""
  prepare_sdk_metadata_once || return 1
  [ "$RESOLVED_SDK_URL" = "$OPENWRT_DOWNLOADS_BASE_URL/snapshots/targets/x86/64/$archive_name" ] || return 1
  [ "$EXPECTED_SDK_SHA256" = 0000000000000000000000000000000000000000000000000000000000000002 ] ||
    fail 'Resolved hash must come from the verified manifest entry'
}

tampered_manifest_is_rejected() {
  OPENWRT_SDK_VERSION=main
  SDK_SHA256=""
  fixture_manifest="${fixture_manifest/0000000000000000000000000000000000000000000000000000000000000002/0000000000000000000000000000000000000000000000000000000000000003}"
  local result
  if result="$(prepare_sdk_metadata_once 2> "$test_root/error")"; then
    fail 'A manifest whose SDK hash was altered after signing must fail'; return 1
  fi
  grep -Fq 'signature verification failed' "$test_root/error" || fail 'Failure must come from signature verification'
}

invalid_archive_hash_is_rejected() {
  EXPECTED_SDK_SHA256=0000000000000000000000000000000000000000000000000000000000000000000
  SDK_CACHE_DIR="$test_root/cache"
  SDK_ARCHIVE="$SDK_CACHE_DIR/sdk.tar.zst"
  printf 'SDK archive bytes\n' > "$test_root/sdk.tar.zst"
  if download_sdk "$test_root/sdk.tar.zst" 2> "$test_root/error"; then
    fail 'An SDK archive with a mismatched SHA-256 must be rejected'; return 1
  fi
  [ ! -f "$SDK_ARCHIVE" ] && [ ! -f "$SDK_ARCHIVE.part" ] ||
    fail 'An unverified SDK archive must not remain in the cache'
}

failed=0
for test_case in latest_release_uses_json stable_sdk_uses_manifest snapshot_sdk_uses_manifest \
  archive_formats_are_supported release_failure_stops_resolution missing_series_stops_resolution \
  malformed_json_is_rejected missing_sdk_is_rejected failed_manifest_is_rejected \
  signed_metadata_is_verified tampered_manifest_is_rejected invalid_archive_hash_is_rejected; do
  : > "$request_log"
  if ("$test_case"); then
    printf 'PASS %s\n' "$test_case"
  else
    printf 'FAIL %s\n' "$test_case" >&2
    failed=$((failed + 1))
  fi
done
[ "$failed" -eq 0 ]
