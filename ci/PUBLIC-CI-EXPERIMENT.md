# Public MATLAB CI experiment

This branch is an experiment, not the complete compatibility workflow. Main and dev keep their existing configuration. No production code, DLL payload, canonical assertion, license enforcement, or credentials are changed.

## Iteration 1: Windows direct .NET diagnostic

- Change: replace this branch's self-hosted precondition and full matrix with one Windows job using official `matlab-actions/setup-matlab@v3` and `run-command@v3`, MATLAB R2026b, and .NET 8. Build the existing managed host and run existing native `TestManagedRuntime.m` tests through MATLAB.
- Reason: distinguish our own earlier guard failure from the actual behavior of public-project automatic licensing with MATLAB directly loading the existing Core DLL. The runtime test initializes the production wrapper with Core's in-memory emulator and verifies managed ticking while MATLAB is busy.
- Constraints: no Python Engine, user license token, account login, paid runner, hardware, or changed MathWorks enforcement. One Windows job, 30-minute timeout. Compatibility and full conformance remain untested by this iteration.
- Result: pending GitHub Actions run. Technical execution does not by itself settle MathWorks support or licensing terms; preserve any actual licensing error.
