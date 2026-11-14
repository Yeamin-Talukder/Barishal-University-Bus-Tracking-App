#!/usr/bin/env bash
# Decides whether this push publishes a new release.
#
# Reads the version from pubspec.yaml ("1.1.0+2": name 1.1.0, build 2). A
# release is made when no tag v<name> exists yet. Stops with an error when
# the new version is not above the last release, or its build number is not
# higher: Android installs an update only when its version code (worked out
# from the build number) is not lower than the installed one, and the app's
# own updater offers only higher version names.
#
# Writes version, build, tag, prev_tag and release (true/false) to
# $GITHUB_OUTPUT, or prints them when run by hand.
set -euo pipefail

out() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1=$2" >> "$GITHUB_OUTPUT"
  fi
  echo "$1=$2"
}

version_of() {
  grep -E '^version:' | head -1 | sed 's/^version:[[:space:]]*//' | tr -d ' \r'
}

full=$(version_of < pubspec.yaml)
name=${full%%+*}
build=${full#*+}
if [ "$build" = "$full" ]; then build=1; fi
tag="v$name"

out version "$name"
out build "$build"
out tag "$tag"

if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
  echo "::notice::$tag is already released. To publish a new release, raise the version in pubspec.yaml (for example 1.0.1+2)."
  out prev_tag ""
  out release false
  exit 0
fi

prev=$(git tag --list 'v*' --sort=-v:refname | head -1)
out prev_tag "$prev"

if [ -n "$prev" ]; then
  prev_full=$(git show "$prev:pubspec.yaml" | version_of)
  prev_name=${prev_full%%+*}
  prev_build=${prev_full#*+}
  if [ "$prev_build" = "$prev_full" ]; then prev_build=1; fi
  highest=$(printf '%s\n%s\n' "$prev_name" "$name" | sort -V | tail -1)
  if [ "$highest" != "$name" ]; then
    echo "::error::Version $name is lower than the last release ($prev_name). Raise it in pubspec.yaml."
    exit 1
  fi
  if [ "$build" -le "$prev_build" ]; then
    echo "::error::Build number $build must be higher than the last release's ($prev_build), or phones will not install the update. Use version: $name+$((prev_build + 1)) in pubspec.yaml."
    exit 1
  fi
fi

out release true
