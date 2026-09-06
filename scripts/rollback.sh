#!/usr/bin/env bash
# rollback.sh - restore container/workspace/ from a snapshot taken by snapshot.sh.
#
# Usage:
#   ./rollback.sh workspace-20260906-143000

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR/../container/workspace"
BACKUPS_DIR="$SCRIPT_DIR/backups"

# Require exactly one argument: the backup folder name to restore from.
if [ $# -ne 1 ]; then
  echo "Usage: $0 <backup-folder-name>" >&2
  echo "Example: $0 workspace-20260906-143000" >&2
  exit 1
fi

BACKUP_NAME="$1"
BACKUP_SRC="$BACKUPS_DIR/$BACKUP_NAME"

# Fail early if the requested backup doesn't actually exist.
if [ ! -d "$BACKUP_SRC" ]; then
  echo "Error: backup not found: $BACKUP_SRC" >&2
  exit 1
fi

# If the current workspace has anything in it, this is a destructive
# operation - warn and require explicit confirmation before wiping it.
mkdir -p "$WORKSPACE_DIR"
if [ -n "$(ls -A "$WORKSPACE_DIR" 2>/dev/null)" ]; then
  echo "Warning: $WORKSPACE_DIR is not empty."
  echo "Restoring '$BACKUP_NAME' will overwrite its current contents."
  read -r -p "Continue? [y/N] " REPLY
  case "$REPLY" in
    y|Y) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

# Clear the current workspace, then copy the backup's contents back in, so the
# restored workspace matches the snapshot exactly (no leftover stale files).
rm -rf "${WORKSPACE_DIR:?}"/*
cp -a "$BACKUP_SRC"/. "$WORKSPACE_DIR"/

echo "Workspace restored from: $BACKUP_SRC"

# Containers are disposable and hold no state of their own (everything
# persistent lives in the bind-mounted workspace we just restored), so
# rolling back means recreating the container fresh, not rolling it back too.
echo "If agent-sandbox is currently running, remove and restart it fresh:"
echo "  docker rm -f agent-sandbox"
echo "  container/run.sh"
