# AGENTS.md

CI that updates and publishes selected packages from `frdlst/void-packages`.
Read README.md first for the moving parts.

## Invariants

- Never build or publish restricted packages: don't set `XBPS_ALLOW_RESTRICTED`
  and don't use `common/travis/prepare.sh` (it sets it).
- CI never pushes the fork's `master`. Only `update/*` branches, which are
  force-pushed and owned by the bot.
- The fork's `master` gets force-pushed by its owner. Nothing may assume
  history is stable; state comes from the published index, not from commits.
- `publish.sh` fails closed: if the current index can't be downloaded, abort
  rather than create a new one (that would delete every other package).
- Upload packages before the index; delete superseded files last.
- Only x86_64 glibc is published.

## Conventions

- Scripts run from the void-packages root inside the pinned container;
  `build.sh`/`update.sh` as user `builder`, `setup.sh`/`publish.sh` as root.
- The container digest appears in both workflows; keep them identical.
- Commit messages in the fork follow upstream style: `<pkg>: update to <ver>.`
- The fork-side trigger file is `.github/workflows/void-packager.yaml` in
  frdlst/void-packages. It must stay a new file (never edit upstream files)
  so rebases onto upstream stay conflict-free.

## Testing

- `bash -n scripts/*.sh`.
- `build.sh` can be dry-run locally from a directory with a fake `./xbps-src`
  that passes `show` through to a real void-packages checkout and echoes `pkg`.
- Monitor CI: `gh run list -R frdlst/void-packages -w void-packager`,
  `gh run view <id> -R frdlst/void-packages --log-failed`.
