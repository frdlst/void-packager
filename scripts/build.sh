#!/bin/bash
# Build every listed package whose template is newer than the published one.
# Never builds an older or equal version, so rewritten history can't downgrade the repo.
# Runs as `builder` from the void-packages root.
set -euo pipefail

list=$(dirname "$0")/../packages.txt
url=https://github.com/frdlst/void-packager/releases/download/repo
idx=$(mktemp -d)
trap 'rm -rf "$idx"' EXIT

# Fail hard: guessing "nothing published" would rebuild everything.
curl -fsSL -o "$idx/x86_64-repodata" "$url/x86_64-repodata"

for pkg in $(grep -v '^[[:space:]]*#' "$list"); do
	want=$(./xbps-src show "$pkg" | sed -n 's/^\(version\|revision\):\t*//p' | paste -sd_)
	have=$(xbps-query -i --repository="$idx" -R -p pkgver "$pkg" 2>/dev/null || true)
	have=${have#"$pkg"-}
	if [ -n "$have" ]; then
		rc=0; xbps-uhelper cmpver "$want" "$have" || rc=$?
		if [ "$rc" != 1 ]; then
			echo "$pkg: published $have, template $want; skipping"
			continue
		fi
	fi
	echo "$pkg: building $want (published: ${have:-none})"
	./xbps-src -j"$(nproc)" pkg "$pkg"
done
