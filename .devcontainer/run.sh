#!/usr/bin/env bash
# Convenience wrapper to run a command (default: interactive shell) inside the
# mpl-dev podman container, with the repo bind-mounted and build caches persisted
# across runs via named volumes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec podman run --rm -it \
    --userns=keep-id \
    -v "${REPO_ROOT}:/workspace" \
    -v mpl-gradle-cache:/home/dev/.gradle \
    -v mpl-m2-cache:/home/dev/.m2 \
    -v mpl-dotnet-cache:/home/dev/.nuget \
    -w /workspace \
    mpl-dev:latest \
    "${@:-bash}"
