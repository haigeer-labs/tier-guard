# Changelog

All notable user-facing changes are documented here. Version numbers follow
[Semantic Versioning](https://semver.org/).

## [0.1.1] - 2026-09-13

### Added

- Select the lowest-cost qualified `model` and `reasoning_effort` for a child
  agent when the parent can read the child-task text before dispatch.
- Audit records, reports, labels, and diagnostics for routing decisions without
  storing raw task text.
- Claude Code v2 pre-dispatch auto-routing for eligible unpinned child tasks;
  the default remains `audit` until its quality gate is met.

### Changed

- Codex and Claude plugin manifests now use the public `0.1.1` release version
  instead of a local Codex cache-busting snapshot.

### Known limitations

- Codex Multi-Agent V2 hooks receive an opaque task token rather than semantic
  child-task text. They therefore remain audit-only and never infer an
  automatic lower- or higher-tier route from that token. Parent-agent plaintext
  pre-routing remains the supported Codex workflow.
