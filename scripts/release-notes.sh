#!/usr/bin/env bash
# release-notes.sh <tag> [previous-tag]
#
# Emits the release notes for a tag on stdout: the curated CHANGELOG section
# for that version, how to install and verify the download, then the commits
# the tag actually contains, grouped by what they did.
#
# Both halves matter, and neither substitutes for the other. The changelog is
# written for the person installing the app -- it says what changed for them.
# The commit list is written by git -- it says what is provably in the tag, and
# it is the half that cannot drift, because nobody maintains it by hand.
#
# GitHub's own --generate-notes is deliberately not used. It builds its list
# from merged pull requests, so a release cut from commits pushed straight to
# main gets a body consisting of a compare link and nothing else.
set -euo pipefail

TAG="${1:?usage: release-notes.sh <tag> [previous-tag]}"
VERSION="${TAG#v}"
PREV="${2:-}"
REPO="redstone-md/mosh-flutter"

if [ -z "$PREV" ]; then
  # The tag before this one, by version order rather than by date: releases
  # get cut out of order often enough that date order lies.
  PREV="$(git tag --list 'v*' --sort=-version:refname | grep -A1 -x -F "$TAG" | tail -n1 || true)"
  [ "$PREV" = "$TAG" ] && PREV=""
fi

# --- curated section from the changelog -------------------------------------
# Matches "## [0.6.9]" and range headings like "## [0.6.9] - [0.6.11]". The
# heading itself is dropped: the release already carries the version.
if [ -f CHANGELOG.md ]; then
  awk -v ver="$VERSION" '
    /^## \[/ {
      if (found) exit
      # Collect every version named in the heading, so a range heading is
      # found by each version it covers.
      line = $0
      n = 0
      while (match(line, /\[[0-9]+\.[0-9]+\.[0-9]+[^]]*\]/)) {
        v = substr(line, RSTART + 1, RLENGTH - 2)
        if (v == ver) n = 1
        line = substr(line, RSTART + RLENGTH)
      }
      if (n) { found = 1; next }
    }
    found { print }
  ' CHANGELOG.md
fi

# --- install + verify ---------------------------------------------------------
cat <<EOF

### Install

**Windows (x64):** download \`mosh-${VERSION}-setup.exe\` below and run it. It
installs per-user under \`%LOCALAPPDATA%\\Programs\\Mosh\` with no admin prompt
and upgrades an existing install in place; message history is kept.

The installer is not code-signed yet, so SmartScreen shows "Windows protected
your PC": click **More info**, then **Run anyway**. Verify the download first:

\`\`\`powershell
(Get-FileHash .\\mosh-${VERSION}-setup.exe -Algorithm SHA256).Hash.ToLower()
# must equal the hash in mosh-${VERSION}-setup.exe.sha256
\`\`\`
EOF

# --- what is provably in it --------------------------------------------------
if [ -n "$PREV" ]; then
  RANGE="$PREV..$TAG"
else
  RANGE="$TAG"
fi

# One line per commit, sorted into the buckets a reader cares about. Merge
# commits carry nothing the commits under them do not.
commits="$(git log --no-merges --pretty='%s|%h' "$RANGE")"
count="$(printf '%s\n' "$commits" | grep -c . || true)"

echo
echo "<details>"
echo "<summary>Commits (${count})</summary>"
echo
printf '%s\n' "$commits" | awk -F'|' -v repo="$REPO" '
  function bucket(subject,   t) {
    if (match(subject, /^[a-z]+(\([^)]*\))?!?:/)) {
      t = substr(subject, 1, RLENGTH)
      sub(/[(!:].*/, "", t)
      if (t == "feat") return "Features"
      if (t == "fix") return "Fixes"
      if (t == "perf") return "Performance"
      return "Internal"
    }
    return "Other"
  }
  {
    b = bucket($1)
    lines[b] = lines[b] "- " $1 " ([`" $2 "`](https://github.com/" repo "/commit/" $2 "))\n"
  }
  END {
    n = split("Features Fixes Performance Other Internal", order, " ")
    for (i = 1; i <= n; i++) {
      b = order[i]
      if (b in lines) {
        printf "**%s**\n\n%s\n", b, lines[b]
      }
    }
  }
'
echo "</details>"

if [ -n "$PREV" ]; then
  echo
  echo "**Full changelog**: https://github.com/${REPO}/compare/${PREV}...${TAG}"
fi
