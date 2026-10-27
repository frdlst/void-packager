#!/bin/bash
# update.sh: for each listed package with a newer upstream version, bump the
# template on update/<pkg> (fresh from the current HEAD) and open or refresh an
# auto-merging PR. update.sh <pkg> does a single package.
# Runs as `builder` from the void-packages root, on master. Needs GH_TOKEN.
set -euo pipefail

if [ $# -eq 0 ]; then
	rc=0
	for pkg in $(grep -v '^[[:space:]]*#' "$(dirname "$0")/../packages.txt"); do
		# Separate process per package: set -e is ignored inside `|| rc=1` contexts.
		"$0" "$pkg" || { echo "::error::$pkg: update failed"; rc=1; }
		git checkout -qf master
	done
	exit $rc
fi

pkg=$1
template=srcpkgs/$pkg/template

new=$(./xbps-src update-check "$pkg" | sed -n "s/^$pkg-.* -> $pkg-//p" | sort -V | tail -n1)
if [ -z "$new" ]; then
	echo "$pkg: up to date"
	exit 0
fi
echo "$pkg: updating to $new"

git checkout -qB "update/$pkg" master
sed -i -e "s/^version=.*/version=$new/" -e "s/^revision=.*/revision=1/" "$template"

# xgensum can't handle per-arch checksums inside case blocks, so for every arch
# the template supports, hash each distfile and swap in the new sum.
# shortcut: plain sha256 only, no "@" content checksums; extend if a listed package uses them.
declare -A sums
for profile in common/cross-profiles/*.sh; do
	arch=$(basename "$profile" .sh)
	./xbps-src -a "$arch" show-avail "$pkg" || continue
	mapfile -t urls < <(./xbps-src -a "$arch" show "$pkg" | sed -n 's/^distfiles:\t*//p')
	mapfile -t old < <(./xbps-src -a "$arch" show "$pkg" | sed -n 's/^checksum:\t*//p')
	[ ${#urls[@]} -eq ${#old[@]} ] || { echo "$pkg/$arch: distfiles/checksum count mismatch" >&2; exit 1; }
	for i in "${!urls[@]}"; do
		u=${urls[i]%%>*}
		[ -n "${sums[$u]:-}" ] || sums[$u]=$(curl -fsSL "$u" | sha256sum | cut -d' ' -f1)
		sed -i "s/${old[i]}/${sums[$u]}/" "$template"
	done
done

title="$pkg: update to $new."
git commit -qam "$title"
git push -qf origin "update/$pkg"

repo=$GITHUB_REPOSITORY
num=$(gh pr list -R "$repo" --head "update/$pkg" --state open --json number -q '.[0].number')
if [ -n "$num" ]; then
	gh pr edit "$num" -R "$repo" --title "$title"
else
	gh pr create -R "$repo" --base master --head "update/$pkg" --title "$title" \
		--body "Automated update by [void-packager](https://github.com/frdlst/void-packager)."
fi
# Waits for the required `build` check (ruleset on master).
gh pr merge "update/$pkg" -R "$repo" --auto --rebase
