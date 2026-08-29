#!/bin/sh
# hermes-docker-testbed — build script
# Usage: ./build.sh [base|testbed|all]   (default: all)
#   base    — rebuild the fork image (loki/hermes-testbed:base) from Dockerfile.base
#   testbed — rebuild the testbed layer (loki/hermes-testbed:testbed)
# Idempotent: assets are fetched once into assets/ and checksum-verified.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
FORK=~/Documents/github/hermes-agent-randlee
FORK_WT=~/Documents/github/hermes-agent-randlee-worktrees/testbed-build
WHEELHOUSE=~/.hermes/wheelhouse

# ── Platform switch (AR: #1097 ships a native aarch64 tarball from 1.4.6 on) ──
# TESTBED_PLATFORM=amd64 (default; qemu emulation on Apple Silicon)
# TESTBED_PLATFORM=arm64 (native arm64; requires the aarch64 atm tarball —
#   provided by the prerelease dispatch via ATM_TARBALL)
TESTBED_PLATFORM="${TESTBED_PLATFORM:-amd64}"
case "$TESTBED_PLATFORM" in
  amd64) ATM_ARCH=x86_64; GRAFT_WHL_ARCH=manylinux_2_17_x86_64; DOCKER_PLAT=linux/amd64 ;;
  arm64) ATM_ARCH=aarch64; GRAFT_WHL_ARCH=manylinux_2_17_aarch64; DOCKER_PLAT=linux/arm64 ;;
  *) echo "FATAL: TESTBED_PLATFORM must be amd64 or arm64"; exit 1 ;;
esac
echo "platform: $TESTBED_PLATFORM ($DOCKER_PLAT)"

ATM_VERSION=${ATM_VERSION_OVERRIDE:-1.4.3}
ATM_ARCHIVE="atm_${ATM_VERSION}_${ATM_ARCH}-unknown-linux-gnu.tar.gz"
ATM_REPO=randlee/atm-core
HERDR_VERSION=v0.8.2
HERDR_ARCHIVE="herdr-linux-${ATM_ARCH}"
HERDR_REPO=herdrdev/herdr
# v0.8.2 release sha256 prefixes (verified): x86_64=976150a1, aarch64=f5561065
case "$ATM_ARCH" in
  x86_64)  HERDR_SHA256_PREFIX=976150a1 ;;
  aarch64) HERDR_SHA256_PREFIX=f5561065 ;;
esac
HERMES_ATM_WHEEL="$WHEELHOUSE/hermes_atm-1.4.2-py3-none-any.whl"
ATM_GRAFT_WHEEL="atm_graft-1.4.3-cp311-abi3-${GRAFT_WHL_ARCH}.whl"
ATM_GRAFT_URL="https://test.pypi.org/packages/$(curl -fsSL https://test.pypi.org/pypi/atm-graft/1.4.3/json | python3 -c "import json,sys; d=json.load(sys.stdin); print([u['url'] for u in d['urls'] if '$GRAFT_WHL_ARCH' in u['filename']][0].split('/packages/')[1])")"

# ── Pre-release override contract (fenix@atm-dev AR integration, 2026-08-28) ──
# ATM_TARBALL=<path>   — use a pre-release atm linux-x86_64 tarball (e.g. the
#                        1.4.5 prerelease-archive CI artifact) instead of the
#                        pinned GitHub release. Checksum recorded in results.
# WHEELS_DIR=<path>    — take hermes_atm/atm_graft wheels from this directory
#                        (the hermes-atm-wheels-linux-x86_64 CI artifact)
#                        instead of the pinned defaults.
# The Dockerfile receives the effective filenames as build args.

TARGET="${1:-all}"

docker context show >/dev/null 2>&1 || { echo "docker not reachable (colima start?)"; exit 1; }

fetch_assets() {
  mkdir -p "$HERE/assets"
  cd "$HERE/assets"

  if [ -n "${ATM_TARBALL:-}" ]; then
    [ -f "$ATM_TARBALL" ] || { echo "FATAL: ATM_TARBALL not found: $ATM_TARBALL"; exit 1; }
    cp -f "$ATM_TARBALL" "$ATM_ARCHIVE"
    ATM_VERSION=$(echo "$ATM_ARCHIVE" | sed "s/atm_\\(.*\\)_${ATM_ARCH}.*/\\1/")
    echo "atm tarball override: $ATM_TARBALL (sha256 $(shasum -a 256 "$ATM_ARCHIVE" | cut -d' ' -f1))"
  else
    [ -f "$ATM_ARCHIVE" ] || gh release download "v$ATM_VERSION" --repo "$ATM_REPO" \
      --pattern "$ATM_ARCHIVE" --pattern checksums.txt --dir .
    grep "linux-gnu" checksums.txt | shasum -a 256 -c - || exit 1
  fi

  if [ -n "${WHEELS_DIR:-}" ]; then
    [ -d "$WHEELS_DIR" ] || { echo "FATAL: WHEELS_DIR not found: $WHEELS_DIR"; exit 1; }
    rm -f hermes_atm-*.whl atm_graft-*.whl
    cp -f "$WHEELS_DIR"/hermes_atm-*.whl "$WHEELS_DIR"/atm_graft-*.whl .
    HERMES_ATM_WHEEL="$(basename "$(ls hermes_atm-*.whl | head -1)")"
    ATM_GRAFT_WHEEL="$(basename "$(ls atm_graft-*.whl | head -1)")"
    echo "wheels override: $HERMES_ATM_WHEEL, $ATM_GRAFT_WHEEL"
  else
    [ -f "$(basename "$HERMES_ATM_WHEEL")" ] || cp "$HERMES_ATM_WHEEL" .
    [ -f "$ATM_GRAFT_WHEEL" ] || curl -fsSL -o "$ATM_GRAFT_WHEEL" "$ATM_GRAFT_URL"
  fi

  if [ ! -f "$HERDR_ARCHIVE" ]; then
    gh release download "$HERDR_VERSION" --repo "$HERDR_REPO" --pattern "$HERDR_ARCHIVE" --dir .
  fi
  shasum -a 256 "$HERDR_ARCHIVE" | grep -q "$HERDR_SHA256_PREFIX" || { echo "herdr checksum mismatch"; exit 1; }

  # Provenance record for AR evidence (uniform `name=<file> sha256=...` lines;
  # parsed by testbed/result.py into the result JSON's provenance block)
  {
    echo "atm_tarball=$ATM_ARCHIVE sha256=$(shasum -a 256 "$ATM_ARCHIVE" | cut -d' ' -f1)"
    for w in hermes_atm-*.whl atm_graft-*.whl; do
      echo "name=$w sha256=$(shasum -a 256 "$w" | cut -d' ' -f1)"
    done
  } > asset-provenance.txt

  echo "assets OK: $(ls | tr '\n' ' ')"
}

build_base() {
  echo "== building loki/hermes-testbed:base (fork image, --extra matrix dropped) =="
  # NEVER build from the primary checkout — it may be stale. Build from a
  # detached worktree freshly reset to origin/main (seam lives on main).
  cd "$FORK"
  git fetch origin main
  if ! git worktree list | grep -q testbed-build; then
    git worktree add --detach "$FORK_WT" origin/main
  fi
  git -C "$FORK_WT" checkout --detach origin/main
  echo "base context: $(git -C "$FORK_WT" log --oneline -1)"
  grep -c "inject_internal_message" "$FORK_WT/gateway/run.py" >/dev/null || \
    { echo "FATAL: seam missing in build context"; exit 1; }
  DOCKER_BUILDKIT=1 docker buildx build --platform "$DOCKER_PLAT" --load \
    -t loki/hermes-testbed:base -f "$HERE/Dockerfile.base" "$FORK_WT"
}

build_testbed() {
  echo "== building loki/hermes-testbed:testbed =="
  cd "$HERE"
  cd assets
  ATM_TARBALL_NAME="$(ls atm_*_${ATM_ARCH}-unknown-linux-gnu.tar.gz | head -1)"
  HERMES_ATM_NAME="$(ls hermes_atm-*.whl | head -1)"
  ATM_GRAFT_NAME="$(ls atm_graft-*.whl | head -1)"
  cd "$HERE"
  echo "testbed artifacts: $ATM_TARBALL_NAME / $HERMES_ATM_NAME / $ATM_GRAFT_NAME"
  DOCKER_BUILDKIT=1 docker buildx build --platform "$DOCKER_PLAT" --load \
    --build-arg ATM_TARBALL="$ATM_TARBALL_NAME" \
    --build-arg HERMES_ATM_WHEEL="$HERMES_ATM_NAME" \
    --build-arg ATM_GRAFT_WHEEL="$ATM_GRAFT_NAME" \
    -t loki/hermes-testbed:testbed .
}

fetch_assets
case "$TARGET" in
  base)    build_base ;;
  testbed) build_testbed ;;
  all)     build_base; build_testbed ;;
  *) echo "usage: $0 [base|testbed|all]"; exit 1 ;;
esac
echo "== build done: $(docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep hermes-testbed) =="
