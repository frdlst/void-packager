# void-packager plan

Automation that keeps selected templates in `frdlst/void-packages` up to date
and publishes the built packages as a signed x86_64 glibc XBPS repository.

## Decisions

- Packages: `dotnet10-sdk-bin`, `bitwarden-cli`, `bitwarden-desktop`, listed in
  `packages.txt`, one per line. The same list is used for auto-update and publishing.
- Arch: x86_64 glibc only.
- Restricted packages are never distributed. CI never sets
  `XBPS_ALLOW_RESTRICTED`, so `xbps-src` refuses to build them.
- Hosting: a rolling GitHub Release (tag `repo`) on `frdlst/void-packager`.
  Git's 100 MB file limit rules out an orphan branch.
- Only the latest version is kept, because the xbps index only lists one version per package.
- No automatic upstream sync. You rebase and force-push `master` by hand. CI
  only ever pushes `update/*` branches.
- Container images are pinned by digest in our workflows. Bumping the digest is a
  manual commit.
- Update PRs auto-merge (rebase) once our own PR check passes.

## Layout

`frdlst/void-packager` holds the logic and no secrets:
```
packages.txt
scripts/bump.sh                    # update-check → edit template → xgensum
scripts/publish.sh                 # index, sign, sync release assets
.github/workflows/build.yaml       # on: workflow_call (input: publish)
.github/workflows/update.yaml      # on: workflow_call
README.md                          # usage, repo URL, key fingerprint
AGENTS.md
```

`frdlst/void-packages` holds the triggers, the secrets, and these new files
(they never conflict on rebase):
```
.github/workflows/void-packager.yaml
srcpkgs/bitwarden-cli/update       # pattern='refs/tags/cli-v\K[\d.]+$'
srcpkgs/bitwarden-desktop/update   # pattern='refs/tags/desktop-v\K[\d.]+$'
srcpkgs/dotnet10-sdk-bin/update    # site=.../release-metadata/10.0/releases.json
                                   # pattern='"latest-sdk": "\K[\d.]+'
```
All three overrides were tested locally. dotnet already reports `10.0.401 -> 10.0.402`.

The fork calls void-packager's workflows as cross-repo reusable workflows. That
means no dispatch tokens, all runs show up in the fork's Actions tab, and the
`actions/checkout` default (the caller's repo and ref) is exactly the commit we
want to build.

```yaml
# void-packages/.github/workflows/void-packager.yaml (sketch)
on:
  pull_request: {paths: ['srcpkgs/**']}
  push: {branches: [master], paths: ['srcpkgs/**']}
  schedule: [{cron: '0 4 * * 1'}]
  workflow_dispatch:
jobs:
  build:
    if: github.event_name == 'pull_request' || github.event_name == 'push'
    uses: frdlst/void-packager/.github/workflows/build.yaml@main
    with: {publish: "${{ github.event_name == 'push' }}"}
    secrets: inherit
  update:
    if: github.event_name != 'pull_request' && (github.event_name != 'push' || github.event.forced)
    uses: frdlst/void-packager/.github/workflows/update.yaml@main
    secrets: inherit
```

## build.yaml

Runs in a digest-pinned `ghcr.io/void-linux/void-glibc-full`.

1. Download `x86_64-repodata` from the release.
2. For each listed package, build it (`xbps-src pkg`) if its template version is
   newer than the indexed one (`xbps-uhelper cmpver`). Older or equal is skipped.
   That way a force-push that accidentally drops a bump can't publish a downgrade.
3. Publish only when `publish` is true (push to master). `xbps-rindex -a` the new
   packages into the repodata, then run `--sign` and `--sign-pkg`. Upload the new
   assets and delete every asset the index no longer references.

On PRs the same job is the check that auto-merge waits for: an x86_64-only build
with no publishing.

## update.yaml

1. For each package, `bump.sh` runs `xbps-src update-check`. If there is a new
   version, it sets `version=` and `revision=1`, then runs `xgensum -i -a <arch>`
   for every arch in `archs` (dotnet has 4 per-arch checksums).
2. Recreate `update/<pkg>` from the current `master` with that single commit and
   force-push it. Open the PR if none is open (`<pkg>: update to <ver>.`), then
   run `gh pr merge --auto --rebase`.

### Force-push handling

- CI never writes `master`, so your force-pushes never race CI writes.
- Open PR branches are rebuilt from the current `master` on every run. A forced
  push to `master` (`github.event.forced`) triggers an immediate update run.
  That way, stale PRs based on pre-rebase history are refreshed before they can
  auto-merge old commits.
- Builds are stateless (the index is the state) and never downgrade, so rewritten
  history doesn't confuse them.
- If you force-push without the bot's merged bump commits, the next update run
  (triggered by that same forced push) re-creates the bump PR.
  Avoid it anyway by doing `git pull --rebase` before rebasing onto upstream.

## Not syncing: what it costs

The fork's `common/` and templates go stale, but dependencies always come from
the live Void mirror. That's fine for months. Eventually a build fails, e.g.
because a pinned makedepend was dropped from the mirror or a new soname is
missing from the stale `common/shlibs`. The fix is your manual rebase.
Note that not syncing doesn't shield you from container changes, since the image
is pulled from ghcr on every run. The digest pin is what does that.

## One-time setup in the fork

- Disable the upstream "Check build" workflow (`gh workflow disable`). That's a
  repo setting, not a file edit, so it survives rebases. Our own PR check
  replaces it. The other upstream workflows are already `disabled_fork`.
- Check that the new `void-packager.yaml` is `active`. GitHub disables
  scheduled workflows in forks by default; `gh workflow enable` fixes it.
- Create a ruleset on `master` that requires the `build` check, with
  **Repository admin** as a bypass actor so your own force-pushes work.
  Until the ruleset exists, `--auto` would merge PRs immediately, so `update.yaml`
  doesn't pass it yet.
- 60-day inactivity rule: cron stays enabled as long as the fork gets commits.
  Monthly dotnet/Bitwarden bumps cover that, and GitHub emails a warning first.

## Secrets (all in the fork)

| Secret | Purpose |
|---|---|
| `VOID_PAT` | Fine-grained PAT. `void-packages`: Contents and Pull requests RW (push `update/*`, open PRs; PRs opened by `GITHUB_TOKEN` wouldn't trigger the check). `void-packager`: Contents RW (release assets). |
| `XBPS_SIGNING_KEY` | RSA private key (PEM). Keep a backup; a new key means every user has to trust it again. |

## Rollout

1. Spike: publish one signed `bitwarden-cli` to the release by hand. Verify
   `xbps-install` from the release URL, and that `xbps-rindex -a` works without
   the old package files present.
2. `build.yaml` + `publish.sh` + the fork's push/PR triggers. Disable "Check build".
3. `update` overrides, `bump.sh`, `update.yaml`, and the cron/forced-push triggers.
4. First update PR → create the ruleset → enable `--auto`.
5. README.md / AGENTS.md.
