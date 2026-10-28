# Ordinary MATLAB CI

`WSS integration compatibility` runs on pull requests to `main` and `dev`, plus
manual dispatch. It separates `Integration behavioral tests` from the three
`Integration compatibility (Windows|Ubuntu|macOS)` jobs, matching C# contexts.
Behavioral checks run real MATLAB unit/runtime tests and Core's shared canonical
catalog through production MATLAB code. Compatibility checks independently load
the selected serial runtime and platform BLE/backend/native ABI assets without
opening a port, scanning, connecting or stimulating. Core has no macOS BLE
backend; the result explicitly reports `unsupported-by-Core`, matching the C#
suite's unsupported-transport scope rather than claiming BLE support.

## Runner/licensing prerequisite

MathWorks' official Setup MATLAB action supports public-project and batch-token
CI licensing, but its [Notes](https://github.com/matlab-actions/setup-matlab#notes)
exclude external language interfaces, including .NET, and direct these workflows
to a separately licensed self-hosted runner. Installing MATLAB with that action
or obtaining a batch token would not qualify these tests. No license, credential,
runner registration or security grant is provisioned here.

The repository owner can select existing licensed runners with JSON label arrays:

| Repository variable | Example value |
| --- | --- |
| `WSS_MATLAB_WINDOWS_RUNNER` | `["self-hosted","Windows","X64","matlab-r2026b"]` |
| `WSS_MATLAB_UBUNTU_RUNNER` | `["self-hosted","Linux","X64","matlab-r2026b"]` |
| `WSS_MATLAB_MACOS_RUNNER` | `["self-hosted","macOS","matlab-r2026b"]` |

Each runner needs separately licensed MATLAB R2026b on PATH, a .NET SDK and .NET 8
runtime, PowerShell, and restored build dependencies. A missing selection falls
back to the corresponding GitHub-hosted OS only to emit a clear failed
prerequisite in the exact required check context. It never substitutes a skipped
or managed-only pass. Actual MATLAB execution must additionally prove license
and runtime availability.

Only Windows has been executed locally. Ubuntu/macOS runner execution is pending.
Do not select a self-hosted runner for untrusted pull requests without reviewing
the runner's isolation and repository trust policy. This work changes no runner
registration, secrets, ruleset or repository-access settings.

Local production checks are `dotnet run --project tests/managed/ManagedHostChecks.csproj -c Release`
and MATLAB `addpath('ci'); runWrapperCi('behavioral'); runWrapperCi('compatibility');`.
Generated evidence goes under ignored `artifacts/ci/`.

Core propagation/promotion/dispatch remains disabled and separate from ordinary
CI. The disabled templates under `automation/templates` are historical examples,
not a second active workflow. Propagation must wait for the owner's later ruleset
and GitHub App setup and explicit authorization.
