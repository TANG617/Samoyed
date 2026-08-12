#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
identity_file="Config/AppleIdentity.xcconfig"

cd "$repository_root"

bundle_id="$({
  awk -F= '
    $1 ~ /^[[:space:]]*SAMOYED_APP_BUNDLE_ID[[:space:]]*$/ {
      value = $2
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$identity_file"
})"

if [[ -z "$bundle_id" || "$bundle_id" != *.* ]]; then
  echo "Unable to derive the previous brand token from $identity_file." >&2
  exit 1
fi

previous_token="${bundle_id##*.}"
lowercase_token="$(tr '[:upper:]' '[:lower:]' <<< "$previous_token" | tr -d '\n')"
uppercase_token="$(tr '[:lower:]' '[:upper:]' <<< "$previous_token" | tr -d '\n')"
failed=0

while IFS= read -r tracked_path; do
  [[ "$tracked_path" == "$identity_file" ]] && continue
  if grep -qiF "$previous_token" <<< "$tracked_path"; then
    echo "Previous brand token remains in tracked path: $tracked_path" >&2
    failed=1
  fi
done < <(git ls-files)

if matches="$(git grep -I -n -i -F "$previous_token" -- . ":(exclude)$identity_file" || true)" \
  && [[ -n "$matches" ]]; then
  echo "Previous brand token remains in tracked content:" >&2
  echo "$matches" >&2
  failed=1
fi

for prohibited in "${lowercase_token}://" "${uppercase_token}_"; do
  if matches="$(git grep -I -n -F "$prohibited" -- . ":(exclude)$identity_file" || true)" \
    && [[ -n "$matches" ]]; then
    echo "Prohibited previous identity remains in tracked content:" >&2
    echo "$matches" >&2
    failed=1
  fi
done

if (( failed != 0 )); then
  exit 1
fi

echo "Brand cleanliness verified; preserved deployment identity is isolated to $identity_file."
