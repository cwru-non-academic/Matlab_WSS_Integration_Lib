# Ordinary MATLAB CI

[WSS integration compatibility](../.github/workflows/wss-compatibility.yml) runs
on pull requests to `main` and `dev`, plus manual dispatch. It separates
`Integration behavioral tests` from the three platform compatibility contexts
(`Windows`, `Ubuntu`, `macOS`). Behavioral checks run real MATLAB unit/runtime tests and
the canonical suites for the verified payload profile through production code.
Compatibility checks independently load the selected serial runtime and platform
BLE/backend/native ABI assets without opening a port, scanning, connecting or
stimulating. A declared macOS backend requires packaged native ABI proof; only an
explicitly identified legacy payload without that backend reports unsupported BLE.

## Hosted native runners and licensing

The committed workflow uses GitHub-hosted Windows and Ubuntu runners and two
required native Mac lanes: ARM64/R2026b on `macos-15` and Intel/R2025b on
`macos-15-intel`. The final macOS context requires evidence from both lanes.
The [native MATLAB action](../.github/actions/native-matlab/action.yml) installs
.NET 8, builds the existing managed host, and invokes official `setup-matlab@v3`
and `run-command@v3`. Intel R2025b is compatibility-only; canonical behavior
remains on R2026b. The workflow does not select runners through
`WSS_MATLAB_*_RUNNER` variables and does not use MATLAB Engine.

Successful hosted execution is technical evidence, not a determination of
MathWorks support or licensing terms. Review the current
[Setup MATLAB notes](https://github.com/matlab-actions/setup-matlab#notes) and the
applicable license. This documentation provisions no runner, license, credential
or security grant.

Local production checks are `dotnet run --project tests/managed/ManagedHostChecks.csproj -c Release`
and MATLAB `addpath('ci'); runWrapperCi('behavioral'); runWrapperCi('compatibility');`.
Generated evidence goes under ignored `artifacts/ci/`.

Ordinary CI is separate from Core propagation and release acceptance. Receiver
workflow definitions and static readiness declarations are committed;
execution still depends on effective enable gates, source-bound proof and human
merges. See [propagation setup](../docs/PROPAGATION-SETUP.md). The disabled templates
under `automation/templates` remain historical examples, not active workflows.

## Native unit-test source contract

`native-test-contract.json` lists the exact test IDs discovered by MATLAB for
this product source. Update it alongside intentional test additions/removals.
The runner checks exact discovered and completed IDs, rejects duplicates, and
requires every result to pass without skips. Evidence includes these IDs and
results; counts alone cannot satisfy a new-source contract.

MATLAB binders retrieve the contract from the verified immutable product-owner
revision, independently of the tooling checkout. Historical sources without a
manifest are accepted only for a frozen reviewed tests-tree and native-runner
blob pair with an authenticated discovery inventory. Unknown historical pairs
fail closed. These compatibility entries are not moving branch or package pins.
Canonical Core scenarios, payload hashes and source/native evidence remain
mandatory and separate from this unit-test inventory.
