#!/usr/bin/env bash
# snapshot.sh - back up the agent's workspace before/after a run, so state can be
# inspected or rolled back later without touching the live workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_SRC="$SCRIPT_DIR/../container/workspace"
BACKUPS_DIR="$SCRIPT_DIR/backups"

# Timestamp the backup folder name so successive snapshots never collide or
# overwrite each other.
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUPS_DIR/workspace-$TIMESTAMP"

# Make sure the backups directory exists before copying into it.
mkdir -p "$BACKUPS_DIR"

# Copy the entire workspace tree into the new timestamped folder. -a preserves
# permissions/timestamps/symlinks; a trailing slash-free source with a new
# destination name copies the directory itself, not just its contents.
cp -a "$WORKSPACE_SRC" "$DEST"

# Report where the snapshot landed so the caller (human or script) can find it.
echo "Backup created at: $DEST"
