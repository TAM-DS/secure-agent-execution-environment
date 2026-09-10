# Secure Agent Execution Environment

### Governing what autonomous AI is allowed to do after reasoning ends and action begins.

AI agents become valuable when they can act.

They can execute code, modify files, call APIs, invoke tools, and make changes to real systems.

That creates a fundamental enterprise problem:

**Capability is not the same thing as authority.**

An agent may be capable of generating a valid command without being authorized to execute it.

This project explores the architectural boundary between those two things.

It implements a constrained execution environment in which agent actions are isolated, evaluated against explicit policy, recorded outside the agent's control, and tested to ensure the controls fail closed.

The objective is not to make autonomous execution risk-free.

It is to make autonomy **bounded, observable, and governable**.

---

## The Architectural Problem

Most agent demonstrations concentrate on whether an agent can successfully complete a task.

Enterprise systems have to answer a harder question:

> What happens when the agent proposes an action we did not intend?

Consider an agent capable of:

* executing shell commands
* creating or deleting files
* calling external APIs
* consuming compute resources
* persisting changes

Every capability expands what the agent can accomplish.

It also expands the blast radius when reasoning, instructions, integrations, or assumptions fail.

The architecture therefore starts from a different assumption:

**Do not trust correct reasoning as the security boundary.**

Reasoning determines what an agent *wants* to do.

Infrastructure and policy determine what it is *allowed* to do.

Those responsibilities should remain separate.

---

# Core Principle

## Agent autonomy should never imply ambient authority.

The system applies a simple rule:

**Reduce authority before execution. Grant authority only for the action that remains.**

Instead of giving the agent broad environmental access and attempting to detect bad behavior afterward, the execution environment begins with constrained authority.

Access must be explicitly introduced.

This creates a boundary between:

**Intent → Proposed Action → Authorization → Execution → Evidence**

The agent controls the first two.

The surrounding architecture controls the rest.

---

# Architecture

The environment uses defense in depth rather than relying on a single security mechanism.

```text
                    AGENT REASONING
                          │
                          ▼
                   PROPOSED ACTION
                          │
                          ▼
              ┌───────────────────────┐
              │    POLICY BOUNDARY    │
              │                       │
              │ Default deny          │
              │ Explicit allow        │
              │ Path restrictions     │
              └───────────┬───────────┘
                          │
                     authorized?
                          │
                          ▼
              ┌───────────────────────┐
              │  EXECUTION BOUNDARY   │
              │                       │
              │ Non-root container    │
              │ Dropped capabilities  │
              │ Read-only root FS     │
              │ Resource limits       │
              │ Scoped workspace      │
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │    NETWORK BOUNDARY   │
              │                       │
              │ Internal network      │
              │ No direct egress      │
              │ Proxy allowlist       │
              └───────────┬───────────┘
                          │
                          ▼
                     REAL WORLD

                          │
                          │ evidence
                          ▼

              ┌───────────────────────┐
              │    AUDIT BOUNDARY     │
              │                       │
              │ Structured decisions  │
              │ Stored externally     │
              │ Outside agent view    │
              └───────────────────────┘
```

No individual control is assumed to be sufficient.

Each layer limits a different failure mode.

---

# Four Independent Trust Boundaries

## 1. Network Boundary

The agent container does not receive unrestricted internet access.

It is attached to an internal Docker network with no direct external route.

A separate proxy bridges the isolated network to an egress-enabled network and restricts outbound destinations through an allowlist.

The design goal is straightforward:

> Network access should be a granted capability, not an environmental default.

An agent attempting an unapproved outbound connection therefore encounters an infrastructure boundary rather than relying on the model to voluntarily comply.

---

## 2. Execution Boundary

Agent code executes inside a non-privileged Docker container configured with:

* Linux capabilities dropped
* `no-new-privileges`
* CPU limits
* memory limits
* execution-time controls
* read-only root filesystem
* temporary `/tmp`
* explicitly scoped writable workspace

The agent cannot see the host filesystem simply because its code is running on the host machine.

Only the designated `/workspace` path is intentionally exposed for persistent work.

This reduces the blast radius of an incorrect or unauthorized action.

---

## 3. Policy Boundary

Before an action is executed, it can be evaluated against an explicit policy.

The policy model is intentionally simple:

```yaml
default: deny
```

Specific operations and paths must be explicitly allowed.

For example:

```text
file_write /workspace/output.py
→ ALLOWED

file_delete /etc/passwd
→ DENIED
```

The important behavior is not the individual deny rule.

It is the default:

**Omission is not permission.**

An action that falls outside the defined authority of the agent fails closed.

---

## 4. Evidence Boundary

Every policy decision produces structured audit evidence containing:

* timestamp
* proposed action
* target
* decision
* matching policy rule

But recording actions is not sufficient if the system performing those actions can also rewrite the record.

The audit location is therefore outside the filesystem exposed to the sandboxed agent.

The stronger architectural principle is:

> **Do not rely on an autonomous system to preserve the evidence required to govern that autonomous system.**

The audit record is not merely protected by another permission rule.

It is outside the agent's filesystem view.

---

# Failure Model

This project assumes that agents can be wrong.

That failure may originate from:

* incorrect reasoning
* ambiguous instructions
* unexpected tool behavior
* malicious or malformed input
* application defects
* runaway execution
* inappropriate action selection

The architecture does not attempt to prove that those failures cannot occur.

Instead, it asks:

> **If reasoning fails, what prevents reasoning failure from automatically becoming system failure?**

That distinction matters.

Model safety and execution safety are related, but they are not identical problems.

A prompt injection might convince an agent to *request* an inappropriate action.

This project addresses the next question:

**Can that requested action actually succeed?**

---

# Threat Model

### In Scope

The architecture demonstrates controls for:

* unauthorized network egress
* unapproved API access
* filesystem access outside the working boundary
* unauthorized file modification or deletion
* runaway resource consumption
* loss of execution accountability
* persistence of unwanted workspace changes

### Explicitly Out of Scope

This project does **not** claim to provide:

* protection from a compromised Docker daemon
* protection from host-kernel exploitation
* production-grade multi-tenant isolation
* complete prompt-injection prevention
* formal verification of agent behavior
* certification as a production security platform

Those boundaries are deliberate.

A credible architecture should state what it cannot guarantee as clearly as what it can.

---

# Recovery Is Part of Governance

Prevention is only one part of operational control.

The project also implements workspace snapshot and rollback.

Because containers are disposable and persistent state is restricted to the designated workspace, that state can be captured and restored independently of the execution environment.

This creates another useful property:

**An agent's ability to change state does not automatically make that state irreversible.**

---

# Verification

Security controls that exist only in architecture diagrams are assumptions.

The important controls in this project are therefore tested in both directions:

```text
Expected behavior       Verification

Allowed network path    succeeds
Denied network path     fails

Allowed filesystem use  succeeds
Denied filesystem use   fails

Allowed policy action   succeeds
Denied policy action    fails closed
```

The repository preserves the resulting evidence alongside the implementation.

This turns statements such as:

> "The agent is isolated."

into testable claims.

---

# Continuous Verification

A self-hosted GitHub Actions runner executes the network, container, and policy tests after changes to `main`.

This is intentionally CI rather than CD.

There is no application deployment target.

The pipeline continuously verifies that the controls the architecture depends upon still behave as expected after the implementation changes.

In other words:

**the infrastructure is both the implementation and the test subject.**

---

# Relationship to Trustworthy AI

This project is one part of a broader architectural question:

## Where should trust boundaries exist when AI systems move from answering questions to making decisions and taking actions?

A trustworthy AI system has multiple stages:

```text
USER INTENT
     │
     ▼
INTERPRETATION
     │
     ▼
REASONING
     │
     ▼
DECISION
     │
     ▼
PROPOSED ACTION
     │
     ▼
AUTHORIZATION
     │
     ▼
EXECUTION
     │
     ▼
EVIDENCE
```

Different failure modes exist at different stages.

My **AI-Ready Data Platform** explores the decision side of that problem: semantic ambiguity, compositional correctness, authorization, and whether individually valid operations can combine into an invalid business decision.

This project explores the execution side:

**Even when an AI system produces an action, what authority should that action actually receive?**

Together they demonstrate two complementary principles:

### Decision boundary

**Trustworthy AI does not eliminate uncertainty. It makes uncertainty explicit, bounded, and governable.**

### Execution boundary

**Trustworthy agents do not eliminate autonomy. They make autonomy explicit, bounded, and governable.**

Or more simply:

> **Bound the uncertainty of the decision.
> Bound the authority of the action.
> Preserve evidence of both.**

---

# What This Project Demonstrates

The value of this project is not Docker configuration by itself.

It demonstrates an approach to designing autonomous systems around explicit trust boundaries:

**Capability ≠ Authority**

**Reasoning ≠ Permission**

**Execution ≠ Trust**

**Logging ≠ Governable evidence unless the actor cannot rewrite it**

**Prevention ≠ Recovery**

And perhaps most importantly:

> **A trustworthy agent architecture should remain governable even when the agent itself is wrong.**

That is the architectural problem this project is intended to explore.
