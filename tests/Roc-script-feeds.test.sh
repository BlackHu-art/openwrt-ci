#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

openwrt_root="$test_root/openwrt"
fake_bin="$test_root/bin"

mkdir -p \
  "$fake_bin" \
  "$openwrt_root/package/base-files/files/bin" \
  "$openwrt_root/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include" \
  "$openwrt_root/feeds/luci/applications" \
  "$openwrt_root/feeds/luci/themes" \
  "$openwrt_root/feeds/packages/lang" \
  "$openwrt_root/feeds/packages/net/aria2" \
  "$openwrt_root/feeds/packages/net/ariang" \
  "$openwrt_root/package" \
  "$openwrt_root/scripts"

printf 'built-in aria2\n' > "$openwrt_root/feeds/packages/net/aria2/.built-in"
printf 'built-in ariang\n' > "$openwrt_root/feeds/packages/net/ariang/.built-in"
: > "$openwrt_root/.config"

printf "hostname='OpenWrt'\n192.168.1.1\n" > "$openwrt_root/package/base-files/files/bin/config_generate"
printf "%s\n" "_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || '')," \
  > "$openwrt_root/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"

cat > "$openwrt_root/scripts/feeds" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$openwrt_root/scripts/feeds"

cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}" in
  clone)
    destination="${!#}"
    mkdir -p "$destination"
    if [[ "$destination" == */luci-app-athena-led ]]; then
      mkdir -p "$destination/root/etc/init.d" "$destination/root/usr/sbin"
      : > "$destination/root/etc/init.d/athena_led"
      : > "$destination/root/usr/sbin/athena-led"
    fi
    ;;
  sparse-checkout)
    shift 2
    for path in "$@"; do
      mkdir -p "$path"
    done
    ;;
  *)
    printf 'Unexpected git command: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fake_bin/git"

cp "$repo_root/scripts/Roc-script.sh" "$openwrt_root/Roc-script.sh"
(
  cd "$openwrt_root"
  PATH="$fake_bin:$PATH" ./Roc-script.sh .config .config
)

for package_name in aria2 ariang; do
  if [[ ! -f "$openwrt_root/feeds/packages/net/$package_name/.built-in" ]]; then
    printf 'Roc-script.sh did not preserve feeds/packages/net/%s\n' "$package_name" >&2
    exit 1
  fi
done
