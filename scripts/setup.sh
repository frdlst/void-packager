#!/bin/bash
# Bootstrap a void-packages checkout for user `builder`.
# Runs as root in the CI container, from the void-packages root.
set -euo pipefail

chown -R builder:builder .
sudo -u builder common/travis/set_mirror.sh
# Not common/travis/prepare.sh: it sets XBPS_ALLOW_RESTRICTED, and restricted
# packages must never be built or published here.
echo XBPS_CHROOT_CMD=uchroot >> etc/conf
sudo -u builder ./xbps-src binary-bootstrap
