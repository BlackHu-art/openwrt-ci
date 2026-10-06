#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
test_group="${1:-all}"
test_path="${2:-all}"
case "$test_group" in
  all | go | frp) ;;
  *) printf 'Unknown test group: %s\n' "$test_group" >&2; exit 1 ;;
esac
case "$test_path" in
  all | firmware | sdk) ;;
  *) printf 'Unknown test path: %s\n' "$test_path" >&2; exit 1 ;;
esac

# Real Git checkouts exercise sparse cloning, file replacement and revision recording.
fixture_root="$test_root/source"
mkdir -p "$fixture_root"/{lang/golang,net/frp,net/nginx,applications/luci-app-frpc,applications/luci-app-frps,lucky,luci-app-lucky}
printf 'updated Go fixture\n' > "$fixture_root/lang/golang/Makefile"
printf 'frp fixture\n' > "$fixture_root/net/frp/Makefile"
printf 'nginx fixture\n' > "$fixture_root/net/nginx/Makefile"
printf 'lucky fixture\n' > "$fixture_root/lucky/Makefile"
printf 'lucky LuCI fixture\n' > "$fixture_root/luci-app-lucky/Makefile"
for app in frpc frps; do
  printf 'LUCI_EXTRA_DEPENDS:= +%s (>=9.9.9)\nLUCI_DEPENDS:=+%s\n' "$app" "$app" \
    > "$fixture_root/applications/luci-app-$app/Makefile"
done
git init -q -b master "$fixture_root"
git -C "$fixture_root" -c core.autocrlf=false add .
git -C "$fixture_root" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
for branch in frp-binary frp nginx main; do
  git -C "$fixture_root" branch "$branch"
done
fixture_commit="$(git -C "$fixture_root" rev-parse HEAD)"
fixture_url="file://$fixture_root"

# Redirect the firmware script's fixed upstream URLs to the local fixture.
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0="url.$fixture_url.insteadOf"
export GIT_CONFIG_VALUE_0=https://github.com/laipeng668/packages
export GIT_CONFIG_KEY_1="url.$fixture_url.insteadOf"
export GIT_CONFIG_VALUE_1=https://github.com/laipeng668/luci
export GIT_CONFIG_KEY_2=core.autocrlf
export GIT_CONFIG_VALUE_2=false

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

assert_updated_go() {
  local build_root="$1"
  local revisions_file="$2"
  grep -Fxq 'updated Go fixture' "$build_root/feeds/packages/lang/golang/Makefile" ||
    fail "$build_root: non-frp build retained the old Go package"
  [ ! -e "$build_root/feeds/packages/lang/golang/old-file" ] ||
    fail "$build_root: stale Go files survived replacement"
  grep -Fq "$(printf '\tmaster\t%s' "$fixture_commit")" "$revisions_file" ||
    fail "$build_root: updated Go checkout was not recorded"
}

assert_frp_dependencies() {
  local build_root="$1"
  shift
  local app
  for app in "$@"; do
    local makefile="$build_root/feeds/luci/applications/luci-app-$app/Makefile"
    if grep -q '^LUCI_EXTRA_DEPENDS:=' "$makefile"; then
      fail "$build_root: $app retained an incompatible version constraint"
    fi
    grep -Fxq "LUCI_DEPENDS:=+$app" "$makefile" ||
      fail "$build_root: $app lost its regular package dependency"
  done
}

seed_old_go() {
  mkdir -p "$1/feeds/packages/lang/golang"
  printf 'old Go fixture\n' > "$1/feeds/packages/lang/golang/Makefile"
  : > "$1/feeds/packages/lang/golang/old-file"
}

run_firmware_case() {
  local case_name="$1"
  shift
  local build_root="$test_root/firmware-$case_name"
  local app
  mkdir -p \
    "$build_root/package/base-files/files/bin" \
    "$build_root/package" \
    "$build_root/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include" \
    "$build_root/feeds/luci/applications" \
    "$build_root/feeds/packages/net" \
    "$build_root/scripts"
  seed_old_go "$build_root"
  : > "$build_root/device.config"
  : > "$build_root/general.config"
  for app in "$@"; do
    printf 'CONFIG_PACKAGE_luci-app-%s=y\n' "$app" >> "$build_root/device.config"
  done
  printf "hostname='OpenWrt'\n192.168.1.1\n" > "$build_root/package/base-files/files/bin/config_generate"
  printf '%s\n' "_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || '')," \
    > "$build_root/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$build_root/scripts/feeds"
  chmod +x "$build_root/scripts/feeds"
  (
    cd "$build_root"
    bash "$repo_root/scripts/Roc-script.sh" device.config general.config
  ) > "$build_root/run.log" 2>&1 || { cat "$build_root/run.log" >&2; fail "Firmware case failed: $case_name"; }
  if [ "$case_name" = no-frp ]; then
    assert_updated_go "$build_root" "$build_root/third-party-sources.txt"
    [ ! -e "$build_root/feeds/packages/net/frp" ] || fail 'Firmware without frp unexpectedly loaded frp'
  else
    assert_frp_dependencies "$build_root" "$@"
    if [ "$#" -eq 1 ]; then
      local other_app=frpc
      [ "$1" != frpc ] || other_app=frps
      [ ! -e "$build_root/feeds/luci/applications/luci-app-$other_app" ] ||
        fail "Firmware unexpectedly loaded luci-app-$other_app"
    fi
  fi
  printf 'PASS firmware %s\n' "$case_name"
}

run_sdk_case() (
  local selection="$1"
  local build_root="$test_root/sdk-$selection"
  local PACKAGES_REPO="$fixture_url"
  local LUCI_REPO="$fixture_url"
  local LUCKY_REPO="$fixture_url"
  local RUNNER_TEMP="$test_root/sdk-temp-$selection"
  local SDK_ROOT="$build_root"
  local PACKAGE_SELECTION="$selection"
  mkdir -p "$RUNNER_TEMP"
  seed_old_go "$build_root"
  source "$repo_root/scripts/SDK-script.sh"
  : > "$SOURCE_REVISIONS_FILE"
  {
    remove_builtin_packages
    load_custom_packages
  } > "$RUNNER_TEMP/run.log" 2>&1 || { cat "$RUNNER_TEMP/run.log" >&2; fail "SDK case failed: $selection"; }
  case "$selection" in
    nginx | luci-app-lucky)
      assert_updated_go "$build_root" "$SOURCE_REVISIONS_FILE"
      [ ! -e "$build_root/feeds/packages/net/frp" ] || fail 'Non-frp SDK selection unexpectedly loaded frp'
      ;;
    *) assert_frp_dependencies "$build_root" frpc frps ;;
  esac
  printf 'PASS SDK %s\n' "$selection"
)

if [ "$test_group" != frp ]; then
  if [ "$test_path" != sdk ]; then
    run_firmware_case no-frp
  fi
  if [ "$test_path" != firmware ]; then
    run_sdk_case nginx
    run_sdk_case luci-app-lucky
  fi
fi
if [ "$test_group" != go ]; then
  if [ "$test_path" != sdk ]; then
    run_firmware_case client-only frpc
    run_firmware_case server-only frps
    run_firmware_case both frpc frps
  fi
  if [ "$test_path" != firmware ]; then
    run_sdk_case luci-app-frpc
    run_sdk_case luci-app-frps
    run_sdk_case frp
  fi
fi
