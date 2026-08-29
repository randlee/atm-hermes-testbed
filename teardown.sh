#!/bin/sh
# hermes-docker-testbed — teardown
# Usage: ./teardown.sh [--purge]
#   default: remove the container only
#   --purge: also remove images and any hermes-testbed volumes
set -eu
NAME=hermes-testbed
docker rm -f "$NAME" >/dev/null 2>&1 && echo "container removed: $NAME" || echo "no container"
if [ "${1:-}" = "--purge" ]; then
  docker rmi loki/hermes-testbed:testbed loki/hermes-testbed:base >/dev/null 2>&1 && echo "images removed"
  docker volume ls --format '{{.Name}}' | grep '^hermes-testbed-' | while read -r v; do
    docker volume rm "$v" >/dev/null && echo "volume removed: $v"
  done
fi
echo "teardown done"
