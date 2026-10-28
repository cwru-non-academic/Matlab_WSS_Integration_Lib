# Public MATLAB CI experiment

This branch is an experiment, not the complete compatibility workflow. Main and dev keep their existing configuration. No production code, DLL payload, canonical assertion, license enforcement, or credentials are changed.

## Iteration 1: Windows direct .NET diagnostic

- Change: replace this branch's self-hosted precondition and full matrix with one Windows job using official `matlab-actions/setup-matlab@v3` and `run-command@v3`, MATLAB R2026b, and .NET 8. Build the existing managed host and run existing native `TestManagedRuntime.m` tests through MATLAB.
- Reason: distinguish our own earlier guard failure from the actual behavior of public-project automatic licensing with MATLAB directly loading the existing Core DLL. The runtime test initializes the production wrapper with Core's in-memory emulator and verifies managed ticking while MATLAB is busy.
- Constraints: no Python Engine, user license token, account login, paid runner, hardware, or changed MathWorks enforcement. One Windows job, 30-minute timeout. Compatibility and full conformance remain untested by this iteration.
- Result: PASS, both existing native runtime tests passed in PR-triggered run https://github.com/cwru-non-academic/Matlab_WSS_Integration_Lib/actions/runs/40745512339 (2m52s). Technical execution does not by itself settle MathWorks support or licensing terms; preserve any actual licensing error.

## Iteration 2: Complete native wrapper suite and distinct platforms

- Change: run the existing full native `runWrapperCi('behavioral')` entrypoint plus managed host checks on Windows. Restore separate Windows, Ubuntu, and macOS compatibility jobs, each using official public-project setup and native `runWrapperCi('compatibility')`. Upload existing JSON evidence from every job.
- Reason: establish whether the successful direct-DLL path supports the complete wrapper CI requirements, including canonical Core scenarios and independent platform loading. Exact existing C# check-context names are retained.
- Constraints: unchanged production DLL payload and shared assertions; no Engine, user token, paid runner, hardware, or licensing-enforcement changes. Four jobs, each bounded to 30 minutes. The current macOS BLE result explicitly remains unsupported-by-Core, not a BLE pass.
- Result: pending GitHub Actions run.
