#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
feed_dir="${1:-feeds/packages}"
fix="$repo_root/patches/packages/miniupnpd-2.3.11.patch"
makefile="$feed_dir/net/miniupnpd/Makefile"

test -f "$makefile" || { echo "Error: miniupnpd Makefile not found: $makefile" >&2; exit 1; }
version="$(sed -n 's/^PKG_VERSION:=[[:space:]]*//p' "$makefile" | tr -d '\r')"
if [ "$version" != 2.3.11 ]; then
  echo "miniupnpd $version: no 2.3.11 compatibility patch needed"
  exit 0
fi

# Backport https://github.com/immortalwrt/packages/pull/2001 at 11ebc02.
# Check the complete feed change before applying it; never leave half a fix.
if git -C "$feed_dir" apply --check "$fix" 2>/dev/null; then
  # This changes patch files, whose context lines intentionally contain whitespace.
  git -C "$feed_dir" apply --whitespace=nowarn "$fix"
  echo 'Applied miniupnpd 2.3.11 patch refresh (ImmortalWrt packages PR #2001)'
elif git -C "$feed_dir" apply --reverse --check "$fix" 2>/dev/null; then
  echo 'miniupnpd 2.3.11 patch refresh is already present'
else
  echo 'Error: miniupnpd 2.3.11 patches changed; review ImmortalWrt packages PR #2001 before rebuilding' >&2
  exit 1
fi
