#!/usr/bin/env bash
set -Eeuo pipefail

release_tag="${1:?Usage: $0 RELEASE_TAG ARTIFACT_DIRECTORY}"
artifact_dir="${2:?Usage: $0 RELEASE_TAG ARTIFACT_DIRECTORY}"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

if [ ! -d "$artifact_dir" ]; then
  printf 'Artifact directory does not exist: %s\n' "$artifact_dir" >&2
  exit 1
fi

declare -A local_asset_names=()
while IFS= read -r -d '' artifact_path; do
  artifact_name="${artifact_path##*/}"
  local_asset_names["${artifact_name,,}"]="$artifact_name"
done < <(find "$artifact_dir" -maxdepth 1 -type f -print0)

if [ "${#local_asset_names[@]}" -eq 0 ]; then
  printf 'No release assets found in: %s\n' "$artifact_dir" >&2
  exit 1
fi

temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
api_error_file="$(mktemp "$temp_root/release-api-error.XXXXXX")"
release_assets_file="$(mktemp "$temp_root/release-assets.XXXXXX")"
trap 'rm -f "$api_error_file" "$release_assets_file"' EXIT

if ! release_id="$(gh api "repos/$GITHUB_REPOSITORY/releases/tags/$release_tag" --jq .id 2>"$api_error_file")"; then
  if grep -q 'HTTP 404' "$api_error_file"; then
    printf 'Release %s does not exist yet; no legacy assets need cleanup.\n' "$release_tag"
    exit 0
  fi
  cat "$api_error_file" >&2
  exit 1
fi

gh api --paginate "repos/$GITHUB_REPOSITORY/releases/$release_id/assets?per_page=100" \
  --jq '.[] | [.id, .name] | @tsv' > "$release_assets_file"

deleted_count=0
while IFS=$'\t' read -r asset_id asset_name; do
  [ -n "$asset_id" ] || continue
  expected_name="${local_asset_names[${asset_name,,}]-}"
  if [ -n "$expected_name" ] && [ "$asset_name" != "$expected_name" ]; then
    printf 'Deleting case-conflicting release asset: %s -> %s\n' "$asset_name" "$expected_name"
    gh api --method DELETE "repos/$GITHUB_REPOSITORY/releases/assets/$asset_id"
    deleted_count=$((deleted_count + 1))
  fi
done < "$release_assets_file"

printf 'Removed %d case-conflicting release asset(s).\n' "$deleted_count"
