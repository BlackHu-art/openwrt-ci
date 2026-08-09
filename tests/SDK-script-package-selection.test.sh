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
