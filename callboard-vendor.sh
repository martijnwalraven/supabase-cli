#!/bin/sh
# Vendors the @supabase/stack closure (stack + its workspace siblings
# config and process-compose) into a consumer repo as dist-carrying
# tarballs, for consumption outside the sibling-checkout tree (the
# callboard adoption's remote-build shape). pnpm pack replaces catalog:
# and workspace:* specs; the consumer's pnpm overrides route the sibling
# names to these tarballs. Same deliberate-bump flow as
# ../workers-sdk/callboard-pack.sh; run `pnpm install` in the consumer
# afterwards.
set -eu

if [ $# -ne 1 ]; then
  echo "usage: callboard-vendor.sh <consumer-vendor-dir>" >&2
  exit 2
fi
VENDOR_DIR=$(cd "$1" && pwd)
ROOT=$(cd "$(dirname "$0")" && pwd)
TSC="$ROOT/node_modules/.pnpm/typescript@6.0.3/node_modules/typescript/bin/tsc"

COMMIT=$(git -C "$ROOT" rev-parse HEAD)
if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no | head -1)" ]; then
  DIRTY=true
else
  DIRTY=false
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

for PKG in stack config process-compose; do
  DIR="$ROOT/packages/$PKG"
  rm -rf "$DIR/dist"
  node "$TSC" -p "$DIR/tsconfig.dist.json"
  pnpm --dir "$DIR" pack --pack-destination "$STAGE" > /dev/null
  mv "$STAGE"/supabase-"$PKG"-*.tgz "$VENDOR_DIR/supabase-$PKG.tgz"
  node -e "
const fs = require('fs');
const path = '$VENDOR_DIR/vendor-manifest.json';
const manifest = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, 'utf8')) : {};
manifest['supabase-$PKG.tgz'] = {
  source: 'Forks/supabase-cli/packages/$PKG',
  commit: '$COMMIT',
  dirty: $DIRTY,
  packedAt: new Date().toISOString(),
};
fs.writeFileSync(path, JSON.stringify(manifest, null, 2) + '\n');
"
  echo "vendored: $VENDOR_DIR/supabase-$PKG.tgz"
done
echo "source $COMMIT, dirty=$DIRTY"
