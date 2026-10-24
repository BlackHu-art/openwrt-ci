#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
# The official refresh supersedes PR #2001 with different patch context.
fixture_commit=e765fb8870b5911992eb4b5a1624ad451e42f4a8
source_hash=91994b127da735b2c97f19992e34420648c0e8c4ace8a4bcb0596e7685c48678

# Optional local inputs allow this real-source regression to run offline.
fixture_dir="${1:-$test_root/download}"
source_archive="${2:-$test_root/miniupnpd-2.3.11.tar.gz}"
if [ "$#" -eq 0 ]; then
  mkdir -p "$fixture_dir/patches"
  for file in Makefile patches/{010-upnp-igdv2-compat,040-improve-logging,900-miniupnpd-format-xml-to-make-some-app-happy}.patch; do
    curl --fail --location --retry 3 --silent --show-error \
      "https://raw.githubusercontent.com/immortalwrt/packages/$fixture_commit/net/miniupnpd/$file" \
      -o "$fixture_dir/$file"
  done
  curl --fail --location --retry 3 --silent --show-error \
    https://github.com/miniupnp/miniupnp/releases/download/miniupnpd_2_3_11/miniupnpd-2.3.11.tar.gz \
    -o "$source_archive"
fi
printf '%s  %s\n' "$source_hash" "$source_archive" | sha256sum -c -

# Use a real sparse checkout to exercise the same path as firmware CI.
feed="$test_root/feed"
mkdir -p "$feed/net/miniupnpd" "$feed/lang/golang" "$feed/applications/luci-app-upnp"
cp -R "$fixture_dir/." "$feed/net/miniupnpd/"
find "$feed" -type f -exec sed -i 's/\r$//' {} +
printf 'Go fixture\n' > "$feed/lang/golang/Makefile"
printf 'LuCI fixture\n' > "$feed/applications/luci-app-upnp/Makefile"
git init -q -b master "$feed"
git -C "$feed" config core.autocrlf false
git -C "$feed" add .
git -C "$feed" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
fixture_revision="$(git -C "$feed" rev-parse HEAD)"

firmware="$test_root/firmware"
mkdir -p "$firmware"/{package/base-files/files/bin,scripts,feeds/packages/lang,feeds/packages/net,feeds/luci/applications}
git init -q "$firmware/feeds/packages"
status_dir="$firmware/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include"
mkdir -p "$status_dir"
printf "hostname='OpenWrt'\n192.168.1.1\n" > "$firmware/package/base-files/files/bin/config_generate"
printf '%s\n' "_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || '')," > "$status_dir/10_system.js"
printf '#!/usr/bin/env bash\nexit 0\n' > "$firmware/scripts/feeds"
chmod +x "$firmware/scripts/feeds"
printf 'CONFIG_PACKAGE_luci-app-upnp=y\n' > "$firmware/device.config"
: > "$firmware/general.config"
(
  cd "$firmware"
  export GITHUB_WORKSPACE="$repo_root"
  export GIT_CONFIG_COUNT=4
  export GIT_CONFIG_KEY_0="url.file://$feed.insteadOf"
  export GIT_CONFIG_VALUE_0=https://github.com/laipeng668/packages
  export GIT_CONFIG_KEY_1="url.file://$feed.insteadOf"
  export GIT_CONFIG_VALUE_1=https://github.com/immortalwrt/packages
  export GIT_CONFIG_KEY_2="url.file://$feed.insteadOf"
  export GIT_CONFIG_VALUE_2=https://github.com/immortalwrt/luci
  export GIT_CONFIG_KEY_3=core.autocrlf
  export GIT_CONFIG_VALUE_3=false
  bash "$repo_root/scripts/Roc-script.sh" device.config general.config
) > "$test_root/firmware.log" 2>&1 || { cat "$test_root/firmware.log" >&2; exit 1; }
package_dir="$firmware/feeds/packages/net/miniupnpd"
diff -r "$feed/net/miniupnpd" "$package_dir"
grep -Fxq "$(printf 'https://github.com/immortalwrt/packages\tmaster\t%s' "$fixture_revision")" "$firmware/third-party-sources.txt"
echo 'PASS firmware accepts official miniupnpd refresh unchanged and records its source'

mkdir "$test_root/source"
tar -xzf "$source_archive" -C "$test_root/source"
source_dir="$test_root/source/miniupnpd-2.3.11"
for file in "$package_dir"/patches/*.patch; do
  patch --batch --forward --fuzz=0 -d "$source_dir" -p1 < "$file" > "$test_root/apply.log" 2>&1 || {
    cat "$test_root/apply.log" >&2
    exit 1
  }
done
test -z "$(find "$source_dir" -name '*.rej' -print -quit)"
grep -Fq 'get_sep(const char * s)' "$source_dir/upnppermissions.c"
grep -Fq 'if (GETFLAG(ALLOWPRIVATEIPV4MASK))' "$source_dir/upnpsoap.c"
grep -Fq 'Listening for UPnP IGD (SOAP/HTTP)' "$source_dir/miniupnpd.c"
echo 'PASS complete official patch series applies to miniupnpd 2.3.11 without fuzz'
