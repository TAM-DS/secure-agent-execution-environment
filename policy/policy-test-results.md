# Policy enforcement test results

All tests run via `policy/enforce.py <action> <path>` against the current
`policy/rules.yaml`:

```yaml
default: deny

allow:
  - action: file_write
    path_prefix: /workspace/
  - action: file_delete
    path_prefix: /workspace/

deny:
  - action: file_delete
    path_prefix: /
    exceptions:
      - /workspace/
```

## Test 1: file_write inside /workspace/

Proves the basic allow path works: an explicit allow rule for `file_write` under
`/workspace/` grants access, and the script exits 0.

```
$ python3 enforce.py file_write /workspace/output.py
ALLOWED
Matching rule: allow: {'action': 'file_write', 'path_prefix': '/workspace/'}
exit: 0
```

## Test 2: file_write outside /workspace/ (default deny)

Proves the fail-closed default: with no allow rule matching, and no deny rule for
`file_write` either, the action falls through to `default: deny` rather than being
permitted by omission.

```
$ python3 enforce.py file_write /etc/passwd
DENIED
Matching rule: default: deny
exit: 1
```

## Test 3: file_delete outside /workspace/ (explicit deny)

Proves the explicit deny rule works: `file_delete` anywhere under `/` is denied,
and this path isn't covered by the rule's `/workspace/` exception, so the deny
applies directly.

```
$ python3 enforce.py file_delete /etc/passwd
DENIED
Matching rule: deny: {'action': 'file_delete', 'path_prefix': '/', 'exceptions': ['/workspace/']}
exit: 1
```

## Test 4: file_delete inside /workspace/ (explicit allow, after adding the rule)

Proves that an `exceptions` entry on a deny rule only means that specific deny
rule doesn't apply there — it does not itself grant access. Before an explicit
`allow: file_delete /workspace/` rule was added, this case fell through to
`default: deny` even though it was excepted from the deny rule. After adding the
allow rule, it now resolves correctly to ALLOWED.

```
$ python3 enforce.py file_delete /workspace/output.py
ALLOWED
Matching rule: allow: {'action': 'file_delete', 'path_prefix': '/workspace/'}
exit: 0
```

## Test 5: path prefix boundary (/workspace2/ vs /workspace/)

Proves prefix matching is boundary-safe: `/workspace2/...` does not falsely match
the `/workspace/` prefix (a naive substring check would incorrectly allow it), so
it correctly falls through to `default: deny`.

```
$ python3 enforce.py file_write /workspace2/output.py
DENIED
Matching rule: default: deny
exit: 1
```
