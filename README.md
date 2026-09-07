# Secure Agent Execution Environment

### A hardened, auditable sandbox for AI agent code execution — designed to answer the question every enterprise adopting agentic AI eventually asks: "what stops the agent from doing something we didn't intend?"

---

## Problem Statement

Agentic AI systems are increasingly given the ability to execute code, read and write files, and call external tools autonomously. This is where most of their value comes from — and also where most of the risk lives. An agent that can run arbitrary commands is, functionally, an unattended process with write access to whatever it touches. Without deliberate boundaries, that translates into real exposure: data exfiltration through unmonitored network calls, unintended file modification or deletion, resource exhaustion from runaway or looping execution, and — perhaps most damaging in a governance context — no reliable record of what the agent actually did.

This is not a hypothetical concern. It is the first question raised in nearly every enterprise conversation about deploying agentic AI beyond a sandboxed demo: *how do we let agents do useful autonomous work without giving them the run of the house?*

This project is a working answer to that question — a local virtual machine configured as a layered containment environment for AI agent execution, built to demonstrate the architectural pattern rather than just describe it.

## Architecture Overview

The design follows a defense-in-depth model: no single control is trusted to be sufficient on its own. Each layer assumes the layer inside it may fail or be circumvented.

```
┌─────────────────────────────────────────────────────────────┐
│  HOST MACHINE                                                │
│  (not reachable from sandbox — outside the trust boundary)   │
└─────────────────────────────────────────────────────────────┘
                              │
                    (isolated network only)
                              │
┌─────────────────────────────────────────────────────────────┐
│  LAYER 1 — NETWORK ISOLATION (Docker bridge networks)        │
│  • agent-sandbox-net is internal — no default route out       │
│  • agent-egress-net has outbound access                       │
│  • agent-proxy (Squid) bridges the two, allowlisting only     │
│    api.anthropic.com — everything else is denied              │
└─────────────────────────────────────────────────────────────┘
                              │
                    (container boundary)
                              │
┌─────────────────────────────────────────────────────────────┐
│  LAYER 2 — CONTAINER (Docker, non-privileged)                │
│  • Dropped Linux capabilities, no privileged mode             │
│  • CPU / memory / execution-time limits enforced              │
│  • Filesystem: scoped bind mount only — no host filesystem    │
│    visibility beyond an explicit /workspace directory         │
└─────────────────────────────────────────────────────────────┘
                              │
                    (execution boundary)
                              │
┌─────────────────────────────────────────────────────────────┐
│  LAYER 3 — POLICY ENGINE                                     │
│  • Every agent-proposed action is checked against a policy    │
│    file before execution is allowed to proceed                │
│  • Denies by default outside explicitly permitted actions     │
└─────────────────────────────────────────────────────────────┘
                              │
                    (write-only, one-way)
                              │
┌─────────────────────────────────────────────────────────────┐
│  LAYER 4 — AUDIT LOG (external to the sandbox)                │
│  • Every command, file access, and network call is recorded   │
│  • Stored outside the sandbox so a compromised or             │
│    misbehaving agent cannot alter or erase its own record     │
└─────────────────────────────────────────────────────────────┘
```

**Operational safety net:** `scripts/snapshot.sh` and `scripts/rollback.sh` back up
and restore `container/workspace/` independent of the four security layers, since
containers are disposable and only `/workspace` holds persistent state.

**Design principle:** each layer is independently useful. The network isolation boundary alone stops the sandbox from reaching anything outside the allowlisted proxy destination. The container boundary alone limits blast radius on the filesystem. The policy engine alone catches a specific class of unauthorized action. The audit log alone guarantees a record survives even if every other control is bypassed. Together, they mean no single misconfiguration or vulnerability compromises the whole system.

## Threat Model

**In scope — what this architecture defends against:**
- Unauthorized network egress (data exfiltration, unapproved API calls, callback to unknown hosts)
- Filesystem access or modification outside the agent's intended working directory
- Resource exhaustion from runaway, looping, or maliciously expensive execution
- Loss of accountability — inability to reconstruct what an agent actually did after the fact
- Persistence of unauthorized changes across sessions (mitigated via snapshot/rollback)

**Explicitly out of scope — what this is not:**
- This is not a defense against a compromised Docker daemon or a host kernel exploit; the Docker network isolation layer assumes the Docker daemon and host kernel are trustworthy.
- This is not a production-grade multi-tenant isolation system; it's a single-operator local sandbox pattern, not a hardened cloud service.
- This does not address model-level risks (prompt injection causing the agent to *request* a harmful action) — it addresses whether that request, once made, can actually succeed. Those are different problems and this project only solves the second one.
- This does not replace a formal security review for any production deployment; it demonstrates the pattern, not a certified implementation.

Naming these boundaries explicitly is deliberate — a system that claims to defend against everything defends against nothing convincingly. This one has a clear, honest edge.

## Setup / Reproduce

The current build uses Docker networks and containers rather than a VirtualBox VM.
Run these in order from the repo root:

1. **Create the network topology** — `network/setup.sh` creates `agent-sandbox-net`
   (an internal bridge network with no default route to the internet), creates
   `agent-egress-net` (a normal bridge network with outbound access), and starts
   `agent-proxy` (Squid, config at `network/squid.conf`) attached to both — the only
   path from the sandbox network out.
2. **Build and run the hardened agent container** — `docker build -t agent-sandbox-base
   container/` builds the non-root image (`container/Dockerfile`), then
   `container/run.sh` runs it attached only to `agent-sandbox-net`, with all Linux
   capabilities dropped, `no-new-privileges`, memory/CPU limits, a read-only root
   filesystem, a `tmpfs` `/tmp`, and `./workspace` bind-mounted as the only writable,
   persistent path.
3. **Gate actions through the policy engine** — `policy/enforce.py <action> <path>`
   evaluates a proposed action against `policy/rules.yaml` (default-deny, explicit
   allow/deny rules with path-prefix matching) and exits 0/1 accordingly, so it can be
   used as a real precondition check rather than just a demo.
4. **Check the audit trail** — every call to `enforce.py` appends a JSON line to
   `audits/decisions.log` (gitignored, since it grows locally on every run).
   `audits/sample-decisions.log` is a committed, frozen example of the format.
5. **Snapshot and roll back workspace state** — `scripts/snapshot.sh` backs up
   `container/workspace/` to a timestamped folder; `scripts/rollback.sh` restores
   from a chosen backup (with a confirmation prompt if the workspace isn't empty).
   Since containers are disposable, rollback doesn't touch the container itself —
   just recreate it with `container/run.sh` after restoring.

### Every layer follows the same pattern

Network, container, and policy are three independent layers, and each one applies
the same default-deny / explicit-allow rule rather than a bespoke scheme per layer:
the sandbox network has no route out except through the proxy's allowlist, the
container denies all filesystem writes except the mounted `/workspace`, and the
policy engine denies all actions except those explicitly allowed in `rules.yaml`.
Each layer was tested in both directions — an allowed case succeeding and a denied
case failing closed — with the results saved alongside the code that implements it:
`network/isolation-test-results.md`, `container/hardening-test-results.md`, and
`policy/policy-test-results.md`.

## Policy Enforcement Example

`policy/enforce.py` loads `policy/rules.yaml` and checks a proposed action (action
type + target path) against it, printing `ALLOWED`/`DENIED` and the specific rule
that matched, then exiting 0 or 1 — so it can gate a real script, not just narrate a
decision. The current ruleset (`policy/rules.yaml`, in full):

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

```
$ python3 policy/enforce.py file_write /workspace/output.py
ALLOWED
Matching rule: allow: {'action': 'file_write', 'path_prefix': '/workspace/'}

$ python3 policy/enforce.py file_delete /etc/passwd
DENIED
Matching rule: deny: {'action': 'file_delete', 'path_prefix': '/', 'exceptions': ['/workspace/']}
```

Actions that fall outside the allowlist are denied by default, not just by an
explicit deny rule — omission is not the same as permission. Full test matrix
(including the boundary case of a deny rule's `exceptions` not itself implying an
allow) is in `policy/policy-test-results.md`.

## Audit Logging

Every call to `policy/enforce.py` appends a structured JSON line to
`audits/decisions.log` — timestamp, action, path, decision, and the specific rule
that matched. A real entry (from `audits/sample-decisions.log`, the committed,
frozen example of the format):

```json
{"timestamp": "2026-09-06T14:15:00.302500+00:00", "action": "file_delete", "path": "/workspace/output.py", "decision": "ALLOWED", "matching_rule": "allow: {'action': 'file_delete', 'path_prefix': '/workspace/'}"}
```

The log path (`audits/`) is resolved relative to the script's own location, not
`/workspace`, so it lands outside the one directory the sandboxed agent container can
write to. This is a stronger guarantee than a permission check: the log doesn't sit
inside the container's mounted filesystem at all, so there's no path traversal or
permission escalation from inside the sandbox that reaches it — it's not merely
access-denied, it's not present in the container's view of the filesystem in the
first place.

## Continuous Integration

A self-hosted GitHub Actions runner lives on this VM and picks up every push to
`main`, running the network, container, and policy test suites automatically
(`.github/workflows/test.yml`) — the same checks described above
(`network/isolation-test-results.md`, `container/hardening-test-results.md`,
`policy/policy-test-results.md`), re-run against the real Docker daemon on every
change instead of only whenever someone remembers to run them by hand.

This is CI, not CD: it's automated *verification* that the sandbox's isolation,
hardening, and policy behavior still hold after a change — there's nothing to
deploy. This project is infrastructure code and its own test subject, not a
service with a deployment target.

---

## Why This Project Exists

This isn't infrastructure for infrastructure's sake. It's a direct answer to the question that comes up in nearly every real conversation about deploying agentic AI in an enterprise context: agents are useful precisely because they act autonomously, and that autonomy is exactly what needs a designed boundary — not an afterthought, not a trust assumption, but an explicit, inspectable containment model. That's the architectural judgment this project is meant to demonstrate.

<!-- CI pipeline verified working as of 2026-09-07 -->
