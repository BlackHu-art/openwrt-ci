#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
helper="$repo_root/scripts/fix-miniupnpd-patches.sh"
fixture_commit=dd29469e222e531bfeab7450bf8df680f7c2735a
source_hash=91994b127da735b2c97f19992e34420648c0e8c4ace8a4bcb0596e7685c48678

# Optional local inputs allow this real-source regression to run offline.
fixture_dir="${1:-$test_root/download}"
source_archive="${2:-$test_root/miniupnpd-2.3.11.tar.gz}"
if [ "$#" -eq 0 ]; then
  mkdir -p "$fixture_dir/patches"
  for file in Makefile patches/{010-upnp-igdv2-compat,020-descr-filter-fix,030-allow-private-fix,040-improve-logging,900-miniupnpd-format-xml-to-make-some-app-happy}.patch; do
    curl --fail --location --retry 3 --silent --show-error \
      "https://raw.githubusercontent.com/immortalwrt/packages/$fixture_commit/net/miniupnpd/$file" \
      -o "$fixture_dir/$file"
  done
  curl --fail --location --retry 3 --silent --show-error \
    https://github.com/miniupnp/miniupnp/releases/download/miniupnpd_2_3_11/miniupnpd-2.3.11.tar.gz \
    -o "$source_archive"
fi
printf '%s  %s\n' "$source_hash" "$source_archive" | sha256sum -c -

feed="$test_root/feed"
mkdir -p "$feed/net/miniupnpd"
cp -R "$fixture_dir/." "$feed/net/miniupnpd/"
# Git for Windows may check out the input patches with CRLF.
find "$feed" -type f -exec sed -i 's/\r$//' {} +
git init -q "$feed"
git -C "$feed" config core.autocrlf false
git -C "$feed" -c core.autocrlf=false add .
git -C "$feed" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
package_dir="$feed/net/miniupnpd"
mkdir "$test_root/source"
tar -xzf "$source_archive" -C "$test_root/source"
source_dir="$test_root/source/miniupnpd-2.3.11"

# Reproduce both independent failures on the actual release tarball.
for name in 020-descr-filter-fix 040-improve-logging; do
  if patch --dry-run --batch --forward -d "$source_dir" -p1 < "$package_dir/patches/$name.patch" > "$test_root/before.log" 2>&1; then
    echo "Expected the original $name patch to fail" >&2
    exit 1
  fi
done
echo 'PASS reproduced stale 020 and 040 patch failures'

bash "$helper" "$feed"
for name in 020-descr-filter-fix 030-allow-private-fix; do
  test ! -e "$package_dir/patches/$name.patch"
done
for file in "$package_dir"/patches/*.patch; do
  patch --batch --forward -d "$source_dir" -p1 < "$file" > "$test_root/apply.log" 2>&1 || {
    cat "$test_root/apply.log" >&2
    exit 1
  }
done
test -z "$(find "$source_dir" -name '*.rej' -print -quit)"
grep -Fq 'get_sep(const char * s)' "$source_dir/upnppermissions.c"
grep -Fq 'if (GETFLAG(ALLOWPRIVATEIPV4MASK))' "$source_dir/upnpsoap.c"
grep -Fq 'Listening for UPnP IGD (SOAP/HTTP)' "$source_dir/miniupnpd.c"
echo 'PASS complete corrected patch series on miniupnpd 2.3.11'

git -C "$feed" diff > "$test_root/once.diff"
bash "$helper" "$feed"
git -C "$feed" diff > "$test_root/twice.diff"
cmp "$test_root/once.diff" "$test_root/twice.diff"
echo 'PASS already-applied upstream fix is unchanged'

for version in 2.3.9 2.3.12; do
  sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$version/" "$package_dir/Makefile"
  git -C "$feed" diff > "$test_root/before.diff"
  bash "$helper" "$feed"
  git -C "$feed" diff > "$test_root/after.diff"
  cmp "$test_root/before.diff" "$test_root/after.diff"
done
echo 'PASS other versions are unchanged'

# Reject an unrecognized patch revision before changing any files.
git -C "$feed" restore --worktree .
find "$feed/net" -type f -exec sed -i 's/\r$//' {} +
printf 'unexpected upstream rewrite\n' > "$package_dir/patches/040-improve-logging.patch"
git -C "$feed" diff > "$test_root/before.diff"
if bash "$helper" "$feed" > "$test_root/rejected.log" 2>&1; then
  echo 'Expected incompatible upstream changes to be rejected' >&2
  exit 1
fi
git -C "$feed" diff > "$test_root/after.diff"
cmp "$test_root/before.diff" "$test_root/after.diff"
echo 'PASS incompatible upstream changes fail without partial edits'

# Exercise the actual firmware customization path with local Git repositories.
git -C "$feed" restore --worktree .
mkdir -p "$feed/lang/golang" "$feed/applications/luci-app-upnp"
printf 'Go fixture\n' > "$feed/lang/golang/Makefile"
printf 'LuCI fixture\n' > "$feed/applications/luci-app-upnp/Makefile"
git -C "$feed" add .
git -C "$feed" -c user.name=Test -c user.email=test@example.invalid commit -qm integration
git -C "$feed" branch -M master
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
test ! -e "$firmware/feeds/packages/net/miniupnpd/patches/020-descr-filter-fix.patch"
test ! -e "$firmware/feeds/packages/net/miniupnpd/patches/030-allow-private-fix.patch"
git -C "$firmware/feeds/packages" apply --reverse --check "$repo_root/patches/packages/miniupnpd-2.3.11.patch"
grep -Fq https://github.com/immortalwrt/packages "$firmware/third-party-sources.txt"
echo 'PASS firmware UPnP selection loads and repairs the real package'
