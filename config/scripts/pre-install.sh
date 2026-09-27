#!/usr/bin/env bash
set -euo pipefail

# /opt is a symlink to var/opt and /usr/local to ../var/usrlocal in these ostree
# images, and neither target exists in a build container. mkdir then fails with
# "File exists", and under `set -e` that aborts the script before it writes
# anything -- which reads as a mysterious no-op rather than a failure.
echo "==> Resolving symlinked system directories..."
mkdir -p /var/opt /var/usrlocal
echo "    /opt     -> $(readlink -f /opt)"
echo "    /usr/local -> $(readlink -f /usr/local)"
