# Architecture Guardrails

## Rôle Seed-Kit

Seed-Kit is the bootstrap, install, and resume assistant for small production-ish nodes.
It is **not** a framework, orchestrator, or autonomous automation engine.

### Mission cible

1. Fresh install
2. Seed-Kit installer
3. `restore <package>` (or guided resume flow)
4. Node opérationnel via manual checkpoints and explicit follow-up

Seed-Kit keeps this as its core mission and does not grow into hidden lifecycle layers.

## Source de vérité

The source of truth is explicit:

- Git repository content
- repository docs
- real validation results

AI chat is useful for reasoning and guidance, but it is **not** a source of truth.

## Anti-bloat policy

Seed-Kit keeps the runtime minimal:

- no new custom planner engines
- no state machines for general orchestration
- no internal framework abstractions before a clear operational need
- no hidden module loaders or orchestration plugins
- no silent global upgrades

Modules own business logic and dependencies; Seed-Kit only orchestrates declared modules.

## Agent workflow expected in this repo

Default human-safe workflow for every change:

1. Audit (read-only inspection)
2. Analysis
3. Proposal
4. Diff review
5. Validation (syntax/checks)
6. Tests
7. Commit
8. Push

For every important discovery, the documentation is updated so the next operator can resume from this repository alone.

## Guardrails opérateur

- Keep operations explicit and human-acknowledged.
- No implicit production network takeover.
- Prefer readable shell scripts and concrete behavior over abstractions.
- No silent system-level mutation in resume workflows.
- If a discovery changes operational behavior, document it in docs before adopting it as default.

## Supervision model

Seed-Kit is a supervised assistant:

- proposes actions
- checks invariants
- applies only when explicitly confirmed

It helps the operator stay safe on constrained nodes (`RPi`, small VPS, network-sensitive targets) and avoids over-automation.

