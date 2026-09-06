# rollback.sh test results

Setup: `container/workspace/file.txt` contained `original content`, snapshotted with
`snapshot.sh` into `scripts/backups/workspace-20260906-144203/`. The workspace was
then dirtied — `file.txt` overwritten with `modified/dirty content` and an extra
`junk.txt` added — to simulate agent activity since the snapshot.

## Test 1: missing backup

Proves the script fails fast and clearly when asked to restore a backup that doesn't
exist, rather than silently doing nothing or wiping the workspace anyway.

```
$ ./rollback.sh workspace-nonexistent
Error: backup not found: /home/tracy/.../scripts/backups/workspace-nonexistent
exit: 1
```

## Test 2: declined confirmation

Proves the confirmation gate actually protects the workspace — declining leaves the
dirty content (`file.txt` still modified, `junk.txt` still present) completely
untouched rather than partially applying the restore.

```
$ echo "n" | ./rollback.sh workspace-20260906-144203
Warning: .../container/workspace is not empty.
Restoring 'workspace-20260906-144203' will overwrite its current contents.
Aborted.
exit: 1

--- workspace contents after decline ---
file.txt
junk.txt
modified/dirty content
```

## Test 3: accepted restore

Proves that, once confirmed, the restore is exact — the workspace ends up matching
the backup precisely: the stray `junk.txt` is gone and `file.txt` is back to its
snapshotted content, not merely overlaid on top of the dirty state.

```
$ echo "y" | ./rollback.sh workspace-20260906-144203
Warning: .../container/workspace is not empty.
Restoring 'workspace-20260906-144203' will overwrite its current contents.
Workspace restored from: .../scripts/backups/workspace-20260906-144203
If agent-sandbox is currently running, remove and restart it fresh:
  docker rm -f agent-sandbox
  container/run.sh
exit: 0

--- workspace contents after restore ---
file.txt
original content
```
