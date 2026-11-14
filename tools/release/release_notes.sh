#!/usr/bin/env bash
# Writes the GitHub release notes for a version.
#
#   tools/release/release_notes.sh <version> <previous tag or ""> <apk folder>
#
# "What's new" comes from release-notes/v<version>.md when that file exists,
# otherwise from the commit messages since the previous release (website
# changes left out). The in-app updater shows these notes under "What's
# new", so the file is the place for wording meant for passengers.
set -euo pipefail

version=$1
prev=$2
apks=$3
arm64="bu-bus-tracker-v$version-arm64.apk"
armv7="bu-bus-tracker-v$version-armv7.apk"

echo "## What's new"
echo
if [ -f "release-notes/v$version.md" ]; then
  cat "release-notes/v$version.md"
else
  range=HEAD
  if [ -n "$prev" ]; then range="$prev..HEAD"; fi
  changes=$(git log --no-merges --format='- %s' "$range" | grep -v -i '^- website' || true)
  if [ -z "$changes" ]; then changes="- Fixes and small improvements."; fi
  echo "$changes"
fi
echo
cat <<EOF
## Download

| File | For |
|---|---|
| \`$arm64\` | Almost every Android phone from the last several years. **Choose this one.** |
| \`$armv7\` | Older 32-bit phones, if the one above will not install. |

Needs Android 7.0 or newer. Download the file on your phone, open it, allow *Install unknown apps* for your browser if asked, then tap **Install**. From version 1.1.0 on, the app also offers new versions itself (Profile → App updates).

## Checksums (SHA-256)

\`\`\`
EOF
(cd "$apks" && sha256sum "$arm64" "$armv7")
echo '```'
echo
echo "Map data © OpenStreetMap contributors."
