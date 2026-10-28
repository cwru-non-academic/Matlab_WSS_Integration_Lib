# Disabled workflow templates

These files are outside `.github/workflows`, use a `.disabled` suffix, and all
jobs have a literal false guard. They are reviewable preparation only. Do not
treat skipped jobs as validation evidence or branch-protection checks.

Names mirror C# integration/CLI contexts exactly. No MATLAB aggregate check names
are introduced. Platform labels remain `Windows`, `Ubuntu`, `macOS`.

Before activation: publish reviewed source and the wrapper gitlink; grant intended
App access; supply licensed, isolated MATLAB R2026b runners, PowerShell, .NET SDK
and runtime 8; validate each OS (only Windows has been executed); pin/review action
versions; implement serial/backend artifact compatibility checks as appropriate;
review self-hosted runner trust boundaries and pull-request policy; complete
interactive input/interrupt verification. Activation needs a separate explicit
decision. Templates currently expose manual triggers only and cannot execute.

Downloaded-artifact preflight/promotion is deliberately not implemented as a
placeholder success workflow. Its immutable archive/source/hash validation must
be implemented first. Preserve canonical names when doing so:

- `Resolve preflight inputs`
- `Preflight behavioral tests`
- `Preflight compatibility (Windows)`, `(Ubuntu)`, `(macOS)`
- CLI `WSS universal candidate provenance`, `CLI general conformance`, and
  `CLI platform compatibility (Windows)`, `(Ubuntu)`, `(macOS)`

Core fan-out, dispatch, remote settings and auto-merge remain unchanged.
