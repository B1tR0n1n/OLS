#!/usr/bin/env bash
# Refresh the engine copies from their own repos and record the commits.
#     tools/sync.sh                 # latest master of both
#     tools/sync.sh <overlord-ref> <sable-ref>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OV_REF="${1:-master}"; SB_REF="${2:-master}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
sync_one() {  # sync_one <name> <url> <ref>
    git clone -q --depth 1 --branch "$3" "$2" "$tmp/$1"
    rsync -a --delete --exclude=.git --exclude=node_modules --exclude=dist --exclude=__pycache__ --exclude=.run \
          --exclude='docker/checkpoints' --exclude='*.pt' "$tmp/$1/" "$HERE/$1/"
    echo "$1  $2  $(git -C "$tmp/$1" rev-parse HEAD)  $(git -C "$tmp/$1" log -1 --format=%cs)"
}
{
    echo "# The engine commits this tree carries (tools/sync.sh refreshes both and rewrites this file)."
    sync_one overlord https://github.com/B1tR0n1n/overlord "$OV_REF"
    sync_one sable    https://github.com/B1tR0n1n/sable    "$SB_REF"
} > "$HERE/ENGINES.lock"
cat "$HERE/ENGINES.lock"
