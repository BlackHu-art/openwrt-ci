#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
source "$repo_root/scripts/SDK-script.sh"

RUNNER_TEMP="$test_root"
SDK_CACHE_DIR="$test_root/cache"
SDK_ARCHIVE="$SDK_CACHE_DIR/sdk.tar.zst"
printf 'complete SDK archive\n' > "$test_root/sdk.tar.zst"
EXPECTED_SDK_SHA256="$(sha256sum "$test_root/sdk.tar.zst" | awk '{print $1}')"
transport_mode=http2-error
fallback_mode=success
SDK_DOWNLOAD_RETRY_COUNT=1

# Reproduce the external transport failure from Actions, including partial
# output. SDK checksum verification and metadata parsing remain real.
curl() {
  local url="" output=/dev/stdout http1=false max_time=0 speed_time=0 retry_max_time=0
  local retry_count=0 retry_all=false connect_timeout=0 speed_limit=0 expected_max_time=120
  local resume=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o) output="$2"; shift 2 ;;
      --http1.1) http1=true; shift ;;
      --max-time) max_time="$2"; shift 2 ;;
      --speed-time) speed_time="$2"; shift 2 ;;
      --retry-max-time) retry_max_time="$2"; shift 2 ;;
      --retry) retry_count="$2"; shift 2 ;;
      --retry-all-errors) retry_all=true; shift ;;
      --connect-timeout) connect_timeout="$2"; shift 2 ;;
      --speed-limit) speed_limit="$2"; shift 2 ;;
      --continue-at) resume="$2"; shift 2 ;;
      --write-out) shift 2 ;;
      -*) shift ;;
      *) url="$1"; shift ;;
    esac
  done

  case "$url" in
    */sdk.tar.zst) expected_max_time=1800 ;;
  esac
  if [ "$max_time" -ne "$expected_max_time" ] || [ "$connect_timeout" -ne 20 ] ||
    [ "$speed_time" -ne 60 ] || [ "$speed_limit" -ne 1024 ]; then
    printf 'Transfer, connection and stall limits do not match the download budget\n' >&2
    return 28
  fi
  if [ "$expected_max_time" -eq 1800 ]; then
    if [ "$http1" != true ] || [ "$resume" != - ] || [ "$retry_count" -ne 0 ]; then
      printf 'Archive requests must use HTTP/1.1 and resume without internal curl retries\n' >&2
      return 28
    fi
  elif [ "$http1" = true ] && {
    [ "$retry_max_time" -ne "$expected_max_time" ] || [ "$retry_count" -ne 2 ] || [ "$retry_all" != true ];
  }; then
    printf 'Fallback must retry all transfer errors within the download budget\n' >&2
    return 28
  fi
  if [ "$http1" = false ] && [ "$transport_mode" = http2-error ]; then
    printf 'partial response' > "$output"
    printf 'curl: (92) HTTP/2 stream was not closed cleanly: PROTOCOL_ERROR\n' >&2
    return 92
  fi
  if [ "$http1" = true ] && [ "$fallback_mode" = failure ]; then
    printf 'partial fallback' > "$output"
    return 28
  fi
  if [ "$http1" = true ] && [ "$fallback_mode" = empty ]; then
    # curl can succeed without touching -o output for HTTP 304 responses.
    return 0
  fi
  if [ "$http1" = true ] && [ "$fallback_mode" = corrupt ]; then
    printf 'corrupt SDK archive\n' > "$output"
    return 0
  fi

  case "$url" in
    https://downloads.example.invalid/sdk.tar.zst)
      cat "$test_root/sdk.tar.zst" > "$output"
      ;;
    https://downloads.example.invalid/.versions.json)
      printf '%s\n' '{"versions_list":["24.10.9","24.10.10"]}' > "$output"
      ;;
    *) printf 'Unexpected URL: %s\n' "$url" >&2; return 22 ;;
  esac
}

fail() { printf '%s\n' "$*" >&2; return 1; }

sdk_download_starts_with_http1() {
  download_sdk https://downloads.example.invalid/sdk.tar.zst || return 1
  cmp "$test_root/sdk.tar.zst" "$SDK_ARCHIVE" ||
    fail 'Archive requests must publish the complete, verified SDK archive'
}

successful_metadata_download_does_not_need_fallback() {
  transport_mode=success
  fallback_mode=failure
  OPENWRT_DOWNLOADS_BASE_URL=https://downloads.example.invalid
  [ "$(resolve_latest_release_version 24.10)" = 24.10.10 ]
}

failed_archive_transfer_preserves_checkpoint() {
  fallback_mode=failure
  if download_sdk https://downloads.example.invalid/sdk.tar.zst; then
    fail 'A failed transfer must fail the SDK download'; return 1
  fi
  [ ! -e "$SDK_ARCHIVE" ] && [ "$(cat "$SDK_ARCHIVE.part")" = 'partial fallback' ] ||
    fail 'Incomplete downloads must remain resumable without becoming verified archives'
}

corrupt_fallback_is_rejected() {
  fallback_mode=corrupt
  if download_sdk https://downloads.example.invalid/sdk.tar.zst 2> "$test_root/checksum-error"; then
    fail 'HTTP/1.1 fallback must not bypass SDK checksum verification'; return 1
  fi
  grep -Fq 'SDK SHA-256 did not match' "$test_root/checksum-error" || {
    fail 'The corrupt fallback must reach SDK checksum verification'; return 1
  }
  [ ! -e "$SDK_ARCHIVE" ] && [ ! -e "$SDK_ARCHIVE.part" ] ||
    fail 'Corrupt downloads must not remain in the SDK cache'
}

metadata_fallback_does_not_emit_partial_response() {
  OPENWRT_DOWNLOADS_BASE_URL=https://downloads.example.invalid
  local version
  version="$(resolve_latest_release_version 24.10)" || return 1
  [ "$version" = 24.10.10 ] ||
    fail 'Fallback must discard partial metadata before parsing the complete JSON'
}

empty_fallback_does_not_reuse_partial_response() {
  fallback_mode=empty
  local response
  response="$(download_http_file https://downloads.example.invalid/.versions.json)" || return 1
  [ -z "$response" ] ||
    fail 'An empty fallback must not emit bytes from the failed first response'
}

local_sdk_file_is_verified() {
  download_sdk "$test_root/sdk.tar.zst" || return 1
  cmp "$test_root/sdk.tar.zst" "$SDK_ARCHIVE"
}

verified_sdk_cache_survives_network_failure() {
  mkdir -p "$SDK_CACHE_DIR"
  cp "$test_root/sdk.tar.zst" "$SDK_ARCHIVE"
  fallback_mode=failure
  download_sdk https://downloads.example.invalid/sdk.tar.zst || return 1
  cmp "$test_root/sdk.tar.zst" "$SDK_ARCHIVE"
}

failed=0
for test_case in sdk_download_starts_with_http1 successful_metadata_download_does_not_need_fallback \
  failed_archive_transfer_preserves_checkpoint corrupt_fallback_is_rejected \
  metadata_fallback_does_not_emit_partial_response local_sdk_file_is_verified \
  verified_sdk_cache_survives_network_failure empty_fallback_does_not_reuse_partial_response; do
  rm -rf "$SDK_CACHE_DIR"
  if ("$test_case") > "$test_root/output" 2>&1; then
    printf 'PASS %s\n' "$test_case"
  else
    cat "$test_root/output" >&2
    printf 'FAIL %s\n' "$test_case" >&2
    failed=$((failed + 1))
  fi
  if [ -n "$(find "$test_root" -maxdepth 1 -name 'openwrt-download.*' -print -quit)" ]; then
    printf 'Temporary download files leaked after %s\n' "$test_case" >&2
    failed=$((failed + 1))
  fi
done
[ "$failed" -eq 0 ]
