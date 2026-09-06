# Container hardening test results

Test run via `container/run.sh`, which launches the `agent-sandbox-base` image with
`--network agent-sandbox-net`, `--cap-drop=ALL`, `--security-opt=no-new-privileges`,
`--memory=512m --cpus=1`, `--read-only`, a `tmpfs` mount at `/tmp`, and a bind mount
of `./workspace` to `/workspace`.

## Test 1: write to /workspace (bind-mounted, persistent)

Proves that the one intentionally writable, persistent location works as designed —
the bind-mounted workspace directory accepts writes despite the root filesystem being
read-only.

```
$ echo hello > /workspace/test.txt && echo WORKSPACE_WRITE_OK
WORKSPACE_WRITE_OK
```

## Test 2: write to / (root filesystem)

Proves that `--read-only` is actually enforced — nothing outside the explicitly
writable mounts (`/workspace`, `/tmp`) can be modified, so a compromised or buggy
process can't tamper with the container's filesystem or persist changes to the image.

```
$ echo hello > /root-test.txt
sh: 1: cannot create /root-test.txt: Read-only file system
ROOT_WRITE_DENIED
```
