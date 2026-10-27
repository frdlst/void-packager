#!/bin/bash
# Add freshly built packages to the release's signed index and delete
# release files the index no longer references (keeps only the latest version).
# Runs from the void-packages root. Needs GH_TOKEN and XBPS_SIGNING_KEY.
set -euo pipefail

repo=frdlst/void-packager
tag=repo
signer="frdlst <devel@frdl.st>"

shopt -s nullglob
new=(hostdir/binpkgs/*.xbps)
if [ ${#new[@]} -eq 0 ]; then
	echo "Nothing to publish."
	exit 0
fi

dir=$(mktemp -d)
key=$(mktemp)
trap 'rm -rf "$dir" "$key"' EXIT
printf '%s\n' "$XBPS_SIGNING_KEY" > "$key"

# Fail hard if the current index can't be fetched: a fresh one would drop every other package.
gh release download "$tag" -R "$repo" -p x86_64-repodata -D "$dir"
cp "${new[@]}" "$dir"
xbps-rindex -a "$dir"/*.xbps
xbps-rindex --sign --signedby "$signer" --privkey "$key" "$dir"
xbps-rindex --sign-pkg --privkey "$key" "$dir"/*.xbps

# Packages before the index, so the index never points at missing files.
gh release upload "$tag" -R "$repo" --clobber "$dir"/*.xbps "$dir"/*.sig2
# shortcut: --clobber deletes then re-uploads, so the index 404s for a few seconds; fine for one user.
gh release upload "$tag" -R "$repo" --clobber "$dir/x86_64-repodata"

keep=$(xbps-query -i --repository="$dir" -R -s '' -p architecture |
	sed -E 's/^([^:]+): ([^ ]+) .*/\1.\2.xbps/')
gh release view "$tag" -R "$repo" --json assets -q '.assets[].name' |
	grep -E '\.xbps(\.sig2)?$' | while read -r asset; do
		if ! grep -qxF "${asset%.sig2}" <<<"$keep"; then
			echo "Deleting superseded $asset"
			gh release delete-asset "$tag" "$asset" -R "$repo" -y
		fi
	done
