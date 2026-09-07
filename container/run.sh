#!/usr/bin/env bash
# run.sh - run the agent sandbox container with hardening flags applied.
#
# Assumes the image has already been built from container/Dockerfile, e.g.:
#   docker build -t agent-sandbox-base container/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR/workspace"
IMAGE="${IMAGE:-agent-sandbox-base}"

# Host-side workspace dir must exist before it can be bind-mounted.
mkdir -p "$WORKSPACE_DIR"

# Only request a pseudo-TTY when actually attached to one (interactive local
# use). CI runners have no TTY, and `-it` there fails outright with
# "cannot attach stdin to a TTY-enabled container".
TTY_FLAGS=()
if [ -t 0 ] && [ -t 1 ]; then
  TTY_FLAGS=(-it)
fi

docker run --rm "${TTY_FLAGS[@]}" \
  --name agent-sandbox \
  `# Only reachable via the internal sandbox network - no default route out.` \
  --network agent-sandbox-net \
  `# Drop every Linux capability; add nothing back since this workload` \
  `# (running arbitrary agent code) needs none of the privileged ones.` \
  --cap-drop=ALL \
  `# Prevent the process (or any child) from gaining more privileges than` \
  `# it started with, even via a setuid/setgid binary.` \
  --security-opt=no-new-privileges \
  `# Cap memory and CPU so a runaway or malicious process can't starve the host.` \
  --memory=512m \
  --cpus=1 \
  `# Root filesystem is read-only; nothing can persist or tamper with the image.` \
  --read-only \
  `# Writable scratch space that lives in memory and disappears on exit -` \
  `# never touches disk, never persists between runs.` \
  --tmpfs /tmp \
  `# The only writable, persistent location: host ./workspace <-> /workspace.` \
  -v "$WORKSPACE_DIR":/workspace \
  "$IMAGE" "$@"
