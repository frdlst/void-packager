# void-packager

Keeps a few templates in [frdlst/void-packages](https://github.com/frdlst/void-packages)
up to date and publishes them as a signed x86_64 glibc XBPS repository.

## Using the repository

```sh
echo 'repository=https://github.com/frdlst/void-packager/releases/download/repo' |
	sudo tee /etc/xbps.d/20-frdlst.conf
sudo xbps-install -S
```

The first sync asks you to import the key. Only accept it if it shows:

```
signed by "frdlst <devel@frdl.st>"
Fingerprint: b2:55:5f:5b:17:07:e2:a0:74:e8:e5:8e:8b:92:6d:39
```

## How it works

Logic lives here; triggers and secrets live in the fork's
`.github/workflows/void-packager.yaml`, which calls the reusable workflows below.

| Fork event | Runs |
|---|---|
| PR touching `srcpkgs/` | `build.yaml` without publishing. This is the `build / build` check auto-merge waits for. |
| Push to `master` | `build.yaml` + publish |
| Weekly cron, manual dispatch, force-push to `master` | `update.yaml` (dispatch also builds) |

- `scripts/update.sh`: for each package in `packages.txt`, `xbps-src update-check`.
  On a new version it bumps `version`/`revision` and every per-arch checksum on
  `update/<pkg>` (recreated from `master` each run), then opens an auto-merging PR.
- `scripts/build.sh`: builds each listed package whose template version is newer
  than the published one. Never older or equal, so rewritten history can't downgrade.
- `scripts/publish.sh`: adds the builds to the release's signed index and deletes
  release files the index no longer references (only the latest version is kept).

Restricted packages are never built: CI never sets `XBPS_ALLOW_RESTRICTED`.

## Adding a package

1. Make sure `./xbps-src update-check <pkg>` in the fork reports new versions;
   if not, add `srcpkgs/<pkg>/update` (`site=`/`pattern=`).
2. Add the name to `packages.txt`.

## Maintenance

- Rebasing the fork: `git pull --rebase` first so you keep the bot's merged
  bumps, then rebase onto upstream and `git push --force-with-lease`. The forced
  push refreshes any open update PRs.
- Container: both workflows pin `void-glibc-full` by digest. Bump both together.
- Secrets in the fork: `VOID_PAT` (fine-grained PAT, Contents + Pull requests RW
  on both repos) and `XBPS_SIGNING_KEY`. Losing the key means every user has to
  re-trust a new one.
- `master` ruleset requires the `build / build` check, with admin bypass for
  your own pushes.
