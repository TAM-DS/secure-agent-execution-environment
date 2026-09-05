# Secure Agent Execution Environment

**A hardened, auditable sandbox for AI agent code execution — designed to answer the question every enterprise adopting agentic AI eventually asks: "what stops the agent from doing something we didn't intend?"**

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
│  LAYER 1 — VIRTUAL MACHINE (VirtualBox, host-only network)   │
│  • No route to host LAN                                      │
│  • Egress allowlist enforced at the VM's own firewall         │
│    (only the AI provider API endpoint is reachable)           │
│  • Snapshot taken before every agent run — full rollback      │
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

**Design principle:** each layer is independently useful. The VM boundary alone stops lateral movement onto the host network. The container boundary alone limits blast radius on the filesystem. The policy engine alone catches a specific class of unauthorized action. The audit log alone guarantees a record survives even if every other control is bypassed. Together, they mean no single misconfiguration or vulnerability compromises the whole system.

## Threat Model

**In scope — what this architecture defends against:**
- Unauthorized network egress (data exfiltration, unapproved API calls, callback to unknown hosts)
- Filesystem access or modification outside the agent's intended working directory
- Resource exhaustion from runaway, looping, or maliciously expensive execution
- Loss of accountability — inability to reconstruct what an agent actually did after the fact
- Persistence of unauthorized changes across sessions (mitigated via snapshot/rollback)

**Explicitly out of scope — what this is not:**
- This is not a defense against a fully compromised host hypervisor or a VirtualBox-level 0-day; the VM boundary assumes VirtualBox itself is trustworthy.
- This is not a production-grade multi-tenant isolation system; it's a single-operator local sandbox pattern, not a hardened cloud service.
- This does not address model-level risks (prompt injection causing the agent to *request* a harmful action) — it addresses whether that request, once made, can actually succeed. Those are different problems and this project only solves the second one.
- This does not replace a formal security review for any production deployment; it demonstrates the pattern, not a certified implementation.

Naming these boundaries explicitly is deliberate — a system that claims to defend against everything defends against nothing convincingly. This one has a clear, honest edge.

## Setup / Reproduce

> Detailed step-by-step instructions live in each subfolder's README. High-level sequence:

1. **Provision the VM** — VirtualBox, host-only or internal network adapter only (no bridged/NAT access to the host LAN). See `/network` for the exact adapter configuration.
2. **Apply network isolation rules** — `iptables`/`nftables` egress allowlist. See `/network` for the ruleset and rationale.
3. **Build the container** — non-privileged Docker container with resource limits and a scoped bind mount. See `/container` for the Dockerfile and run configuration.
4. **Load the policy engine** — the pre-execution policy file and enforcement hook. See `/policy` for the ruleset format and examples.
5. **Enable audit logging** — configure the external log destination before running any agent task. See `/audit` for the logging configuration and a sample redacted log.
6. **Snapshot before every run** — automation scripts for VM snapshot/rollback live in `/scripts`.

## Policy Enforcement Example

The policy engine intercepts every agent-proposed action before it executes, checking it against an explicit allow/deny ruleset. A minimal example (full ruleset and engine code in `/policy`):

```yaml
# policy/rules.yaml — illustrative excerpt
default: deny

allow:
  - action: file_write
    path_prefix: /workspace/
  - action: network_call
    destination: api.anthropic.com

deny:
  - action: file_delete
    path_prefix: /
    exceptions: [/workspace/]
  - action: network_call
    destination: "*"          # everything not explicitly allowed above
```

Actions that fall outside the allowlist are denied and logged — not silently blocked, but recorded as a denied attempt, since a denied action is itself a signal worth capturing.

## Audit Logging

Every command executed, file touched, and network call made by the agent is written to a log store outside the sandbox boundary — so the record survives even if the sandbox itself is compromised or the agent behaves unexpectedly. A redacted sample entry (see `/audit` for full format and configuration):

```json
{
  "timestamp": "2026-09-05T14:32:07Z",
  "action": "file_write",
  "path": "/workspace/output.py",
  "result": "allowed",
  "policy_rule_matched": "file_write:/workspace/"
}
```

---

## Why This Project Exists

This isn't infrastructure for infrastructure's sake. It's a direct answer to the question that comes up in nearly every real conversation about deploying agentic AI in an enterprise context: agents are useful precisely because they act autonomously, and that autonomy is exactly what needs a designed boundary — not an afterthought, not a trust assumption, but an explicit, inspectable containment model. That's the architectural judgment this project is meant to demonstrate.
