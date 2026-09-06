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

## Test 3: proxied request to api.anthropic.com (allowed destination)

Proves that the hardened, network-isolated container (`agent-sandbox-net` only, no
default route to the internet) can still reach the one allowlisted destination by
routing through `agent-proxy:3128`. `curl` isn't present in this minimal, read-only,
non-root image, so the request was made with Python's `urllib` instead — same proxy,
same TLS/HTTP path, equivalent signal.

```
$ export http_proxy=http://agent-proxy:3128 https_proxy=http://agent-proxy:3128
$ python3 -c '
import urllib.request, urllib.error
try:
    r = urllib.request.urlopen("https://api.anthropic.com", timeout=10)
    print("STATUS:", r.status)
except urllib.error.HTTPError as e:
    print("HTTP_ERROR_STATUS:", e.code, e.reason)
except Exception as e:
    print("FAILED:", type(e).__name__, e)
'
HTTP_ERROR_STATUS: 404 Not Found
```

The `404` is expected — it's Anthropic's API responding to a bare `GET /` (it expects
`POST /v1/messages`), which confirms the request reached the real service.

## Test 4: proxied request to google.com (disallowed destination)

Proves that the same hardened container, through the same proxy, cannot reach any
destination outside the allowlist — Squid rejects the `CONNECT` tunnel before it's
ever established.

```
$ export http_proxy=http://agent-proxy:3128 https_proxy=http://agent-proxy:3128
$ python3 -c '
import urllib.request, urllib.error
try:
    r = urllib.request.urlopen("https://google.com", timeout=10)
    print("STATUS:", r.status)
except urllib.error.HTTPError as e:
    print("HTTP_ERROR_STATUS:", e.code, e.reason)
except Exception as e:
    print("FAILED:", type(e).__name__, e)
'
FAILED: URLError <urlopen error Tunnel connection failed: 403 Forbidden>
```
