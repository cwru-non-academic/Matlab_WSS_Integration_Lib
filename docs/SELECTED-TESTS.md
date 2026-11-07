# Independently selected MATLAB native tests

The trusted Core bootstrap authenticates the frozen plan before calling
`.github/scripts/Invoke-SelectedMatlabTests.ps1` from its trusted bootstrap
checkout. The family helper binds a clean, distinct checkout to the all-or-none
`TestRoot`, `TestSha`, `TestRepository`, `TestSelectionId` tuple; an ID by itself
is not authorization. It does not fetch or select refs or execute selected
`.github`, `ci`, release validators, product `src`, or build projects.

The selected checkout contains `tests/test-contract.json` with schema
`wss-matlab-tests/v1`, role `wrapper` or `cli`, test directory `tests`, and
conformance directory `conformance`. These are exact fixed paths, not configurable
entrypoints. All native `.m` tests and conformance sources are copied with their
hashes verified to a disposable test-only tree. Selected managed C# projects are
not evaluated. The trusted product managed lifecycle gate remains mandatory.

The wrapper helper handles both roles. Supply fixed `ProductRoot`, `ProductSha`,
`PayloadRoot`, and a new external `WorkRoot`; CLI also requires `WrapperRoot` and
`WrapperSha`. `PayloadRoot` must contain the canonical projection plus its valid
`payload-source.json`. Original source checkouts stay clean. Git exports at the
fixed product SHAs create disposable products; only their payload directories
receive the verified projection. The trusted product baseline config, canonical
fixture hash, projection inventory and hashes, managed runtime, and existing
native CI behavioral and compatibility gates all run before selected tests.
Existing propagation, receipt, and release validation are unchanged and remain
required independently. No selected test result can replace those gates.

The additional selected suite uses fixed product source and payload paths.
Wrapper conformance receives the product factory, payload, and single/multi
stage. CLI conformance and compatibility receive explicit product and wrapper
roots. Tests use `WSS_MATLAB_PRODUCT_ROOT` for product-owned configuration and
`WSS_MATLAB_WRAPPER_ROOT` for the fixed wrapper. Selected tests are native MATLAB
code, not a security sandbox; their repository and SHA must be authenticated by
the trusted bootstrap before invocation.

Evidence includes original `product_root`, `product_sha`, `wrapper_root`,
`wrapper_sha`, `test_root`, `test_sha`, `test_repository`, `test_selection_id`,
`test_contract_sha256`, fixture and projection digests, and the selected summary
hash. Source bindings, staged source hashes, and payload hashes are checked again
after execution. Only a completed real native run emits passed evidence. No
physical transport is exercised. This standalone adapter does not activate a
workflow or grant frozen-plan authorization.

Run binding regressions with PowerShell:
`pwsh -NoProfile -File .github/scripts/tests/Test-MatlabTestSource.ps1`.
These tests prove binding and fail-closed checks, not native payload compatibility.
