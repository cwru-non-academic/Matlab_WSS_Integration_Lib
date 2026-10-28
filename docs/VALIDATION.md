# Initial local validation

Executed on Windows with MATLAB `26.2.0.3386108 (R2026b)` and CLR `.NET 8.0.29`.
No physical transport or stimulation was used. Checks ran against the final
files under `C:\Users\Owner\Documents\Github`.

| Boundary | Result |
| --- | --- |
| Managed host build/lifecycle probes | Passed; independent ticking, serialized commands, disposal, initialization failure, tick failure |
| MATLAB Code Analyzer | 0 findings |
| MATLAB wrapper/app unit and runtime tests | 9 passed |
| Production MATLAB wrapper/Core emulator | 10 canonical catalog scenarios passed |
| Production CLI factory/Core emulator | 10 canonical catalog scenarios passed |
| Windows compatibility, separate from behavior | Serial runtime selection and BLE/backend/native ABI load-only checks passed through both entry points |
| Blocking CLI input double and real MATLAB interruption | quit → interrupt → quit passed with tick progress, synchronous disposal and reset checks |
| Focused independent code review | Inactive reset guard and asynchronous pause observation findings fixed; follow-up reported no supported findings |
| Core payload provenance | All 25 payload file SHA-256 hashes matched the Python reference revision |
| MIT license | Application and library Git blob `99152be7a8c4cc0b25e9c4a17b6eb22e5655ef82` |
| Git whitespace checks | Passed for both unstaged diffs and existing staged CLI submodule changes |
| Generated-output ignore checks | Managed bin/obj and validation artifacts ignored |

The .NET host checks ran with:

```powershell
dotnet run --project tests/managed/ManagedHostChecks.csproj -c Release
```

MATLAB checks selected `dotnetenv('core',Version='8')`, added the wrapper/app
source paths for the process, analyzed all MATLAB sources, ran `runConformance`,
`runCliConformance` through the app's production factory, and `runtests` for both
repositories. Ignored evidence is retained at `artifacts/matlab-validation.log`
and `artifacts/validation.json` in the wrapper checkout.

The MATLAB conformance source port preserves the canonical catalog and 18
assertion sites. It is not the byte-identical NUnit fixture; equivalence beyond
these passing cases still merits review. Failures aggregate across scenarios;
individual MATLAB scenarios currently fail at their first failed assertion.
The transient pause assertion now uses a cancellation-aware emulator send gate
so Core's separate asynchronous worker cannot complete the edit before an actual
paused state is observed. Normal commands do not use that gate.

The Engine harness command (using an existing Python interpreter) is:

```powershell
python ../CLI_Matlab_WSS_Application/tests/engine/check_interactive_lifecycle.py --matlab-root 'C:/Program Files/MATLAB/R2026b' --wrapper-root .
```

It calls the real production CLI through MATLAB Engine and temporarily shadows
only `input` with a blocking test double. It verifies tick progression while
waiting, then actual MATLAB Engine cancellation and cleanup; it is not a native
keyboard/UI check. Evidence is in ignored `artifacts/engine-lifecycle.log`.

Unverified: native console `input` and keyboard Ctrl+C, physical-device behavior,
Ubuntu/macOS execution and older CLR/namespace compatibility. An isolated native
console check reached MATLAB's input prompt, but the execution tool could not
send input to it. Its process tree was identified and stopped. The manual
`conformance/checkBlockedInput.m` remains available for a native console.

This record describes the local baseline before its authorized main bootstrap.
Published revisions and the consumer pin are recorded in Git. No dispatch,
GitHub App setting or Core fan-out change is part of this implementation.
Disabled templates outside `.github/workflows`
separate behavioral/general conformance from Windows/Ubuntu/macOS compatibility
jobs and retain the exact C# check context names. Each job also has a literal
false guard. Licensed runners, OS validation, published commits/gitlink and
reviewed App access are prerequisites for a separate activation decision.
