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

sdk_root="$(mktemp -d)"
trap 'rm -rf "$sdk_root"' EXIT

for config_file in configs/Packages.config configs/x86-64.config configs/JDCloud.config; do
  SDK_ROOT="$sdk_root"
  PACKAGE_CONFIG_FILES="$config_file"
  load_config_files

  if grep -Eq '^CONFIG_(PACKAGE_(aria2|ariang|luci-app-aria2)|ARIA2_)' "$SDK_ROOT/.config"; then
    printf 'Aria2 config entries still loaded from: %s\n' "$config_file" >&2
    exit 1
  fi
done
