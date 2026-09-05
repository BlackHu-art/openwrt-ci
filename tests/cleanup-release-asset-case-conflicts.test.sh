#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

artifact_dir="$test_root/artifacts"
fake_bin="$test_root/bin"
mkdir -p "$artifact_dir" "$fake_bin"

: > "$artifact_dir/IPQ60XX.config"
: > "$artifact_dir/IPQ60XX.config.buildinfo"
: > "$artifact_dir/IPQ60XX.Packages.tar.gz"

cat > "$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >> "$GH_CALL_LOG"

if [[ "$*" == *'/releases/tags/IPQ60XX'* ]]; then
  printf '123\n'
elif [[ "$*" == *'/releases/123/assets?per_page=100'* ]]; then
  printf '11\tipq60xx.config\n'
  printf '12\tIPQ60XX.config.buildinfo\n'
  printf '13\tipq60xx.Packages.tar.gz\n'
  printf '14\tunrelated.bin\n'
elif [[ "$*" == *'--method DELETE'* ]]; then
  :
else
  printf 'Unexpected gh invocation: %s\n' "$*" >&2
  exit 1
fi
EOF
chmod +x "$fake_bin/gh"

export GH_CALL_LOG="$test_root/gh-calls.log"
export GH_TOKEN=test-token
export GITHUB_REPOSITORY=example/openwrt-ci

PATH="$fake_bin:$PATH" bash "$repo_root/scripts/cleanup-release-asset-case-conflicts.sh" IPQ60XX "$artifact_dir"

if ! grep -q -- '--method DELETE repos/example/openwrt-ci/releases/assets/11' "$GH_CALL_LOG"; then
  printf 'Lowercase config asset was not deleted.\n' >&2
  exit 1
fi

if ! grep -q -- '--method DELETE repos/example/openwrt-ci/releases/assets/13' "$GH_CALL_LOG"; then
  printf 'Lowercase package archive was not deleted.\n' >&2
  exit 1
fi

if grep -q -- '--method DELETE repos/example/openwrt-ci/releases/assets/12' "$GH_CALL_LOG"; then
  printf 'Exact-case asset was incorrectly deleted.\n' >&2
  exit 1
fi

if grep -q -- '--method DELETE repos/example/openwrt-ci/releases/assets/14' "$GH_CALL_LOG"; then
  printf 'Unrelated asset was incorrectly deleted.\n' >&2
  exit 1
fi
