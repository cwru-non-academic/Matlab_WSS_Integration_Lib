# WSS MATLAB Integration Library

Reusable MATLAB access to WSS Core. Applications and GUIs consume this library;
console input and command parsing belong to
[`CLI_Matlab_WSS_Application`](https://github.com/cwru-non-academic/CLI_Matlab_WSS_Application).

## Layout

- `src/+wss/`: `WssConfig`, `StimulationController`, assembly loading.
- `managed/`: a small .NET tick/lifecycle host; no MATLAB callbacks.
- `Cs_Libraries/`: versioned Core/dependency payload, including separate backend assets.
- `Config/`: reusable configuration examples; consumers supply their own runtime paths.
- `tests/`: managed lifecycle checks and MATLAB configuration/lifecycle checks.
- `conformance/`: Core's canonical catalog exercised through the MATLAB public API.

This initial port follows Python wrapper revision
`79322a82d285cc526c77ea660beb2993cb04f5d9`. Payload provenance and hashes are in
`Cs_Libraries/payload-source.json`. No downloaded or locally built substitute Core
is silently selected.

## Build and load

Build the managed host with an installed .NET SDK:

```powershell
dotnet build managed/Wss.Matlab.Managed.csproj -c Release
```

Use a MATLAB release with a supported .NET runtime. The initial target is Windows
with modern Core namespaces; older namespace layouts and Linux/macOS transport
behavior have not been validated. Choose the CLR explicitly in a fresh MATLAB
session before any .NET calls. For a release that supports .NET 8 selection:

```matlab
dotnetenv("core", Version="8");
addpath(fullfile(pwd, 'src'));
config = wss.WssConfig('ConformanceMode', true);
controller = wss.StimulationController(config);
cleanup = onCleanup(@() controller.Shutdown());
controller.Initialize();
controller.Ready()   % asynchronous setup may still be in progress
```

`dotnetenv` is a caller decision and can persist between MATLAB sessions; this
library does not change it. Consult MathWorks'
[runtime documentation](https://www.mathworks.com/help/matlab/ref/dotnetenv.html)
and [assembly loading guide](https://www.mathworks.com/help/matlab/matlab_external/building-a-net-application-for-matlab-examples.html)
for the installed release. The managed host targets `netstandard2.0`; the complete
payload and selected runtime still require execution checks together.

`TestMode=true` selects Core's simulated transport. `ConformanceMode=true` selects
the in-memory emulator and exposes `GetConformance()`. They are mutually exclusive.
`Transport` selects `serial` (default), `ble`, `test`, or `conformance`.
For BLE, supply `BleAutoSelect=true`, `BleDeviceName`, or `BleDeviceId`; these
map directly to Core's existing `BleNusTransportOptions`. Device-ID precedence,
discovery and connection remain Core behavior. For example:

```matlab
config = wss.WssConfig('Transport', 'ble', 'BleDeviceName', 'WSS');
```

Initialize the controller to start a live connection. The public
`wss.createTransport(config)` factory constructs the selected Core transport
without scanning or connecting; its caller owns disposal. Backend loading uses
only the selected platform's packaged assets. The legacy payload supports
Windows/Linux BLE loading; macOS BLE requires the newer Core MacOS backend and
native bridge. A missing selected backend raises `wss:MissingBleBackend`. Construction alone never opens a transport. All development checks use
the emulator or managed probes; no hardware execution has been performed.

## Public surface and lifecycle

The facade preserves Python names such as `Initialize`, `Shutdown`, `Ready`,
`Started`, `StimulateAnalog`, `StimulateNormalized`, `StimWithMode`,
`UpdateEventRatio`, parameter access, channel settings and optional Basic methods.
Finger names and `chN` map to one-based channel identifiers. Target `0` means
broadcast; `1`, `2`, `3` identify devices. Invalid aliases/targets fail explicitly.
Core owns stimulation units, bounds, normalization and protocol semantics.

The managed thread calls `Tick` independently of the MATLAB execution queue.
Ticks and public facade operations share a lock. The configured interval is a
best-effort delay between completed ticks, not a real-time guarantee. A tick
failure attempts a stop and is exposed via `LastTickError`; subsequent calls
fail. `TickCount` supports verification during blocking input and busy MATLAB.

For conformance's transient runtime-edit pause assertion, an optional output
from `UpdateEventRatio` observes the real paused state while an emulator-only
send gate prevents Core's independent setup worker from finishing the edit.
The gate honors cancellation and releases in `finally`; ordinary no-output
commands remain ungated. This keeps all 18 canonical assertion sites without
depending on MATLAB sampling a short asynchronous state transition.

Use `onCleanup` before `Initialize` so normal errors and Ctrl+C unwind through
`Shutdown`. Shutdown waits for in-flight managed work, then attempts broadcast
stop, shutdown and disposal. It is idempotent. Forced process termination cannot
run cleanup. The log path currently receives managed-host lifecycle/error
diagnostics; Core's own default sink is unchanged. Config controllers returned by
`GetCoreConfigCTRL`/`GetModelConfigCTRL` are raw managed objects; callers must not
mutate them concurrently with ticking.

## Verification

Managed checks, requiring no MATLAB and no hardware:

```powershell
dotnet run --project tests/managed/ManagedHostChecks.csproj -c Release
```

After installing MATLAB, from this repository:

```matlab
addpath('src');
% Select supported CLR before loading the payload, as above.
assertSuccess(runtests('tests'));
addpath('conformance');
results = runConformance();
```

Conformance uses the production MATLAB wrapper and Core evaluator, including the
initialization, analog, six normalized, runtime edit and stop scenarios. The
MATLAB port preserves the 18 assertion sites in the canonical C# fixture at
SHA-256 `1cdfb9448a1776011eadc9aef8356362216032013a4f268f50242746c50a0b44`;
it is a source port, not the byte-identical NUnit fixture. Equivalence is pending
MATLAB execution and review. Failures are collected across scenarios.

The initial checks ran on MATLAB R2026b (`26.2.0.3386108`) with .NET 8 on Windows:
managed host checks passed; all 10 catalog scenarios passed through the wrapper
and all 10 through the CLI factory. All nine MATLAB unit/runtime tests passed,
including busy-MATLAB tick progression, failed assembly loading, and normal
CLI quit/command-failure disposal. MATLAB Code Analyzer reported zero findings
at that checkpoint. These are emulator checks, not physical-device qualification.

The CLI's MATLAB Engine harness passed a quit/interruption/quit sequence with
a blocking input double, real MATLAB Engine cancellation, background tick
progress and synchronous disposal/reset checks. Native console `input` and
keyboard Ctrl+C remain manual checks: the execution tool cannot deliver input
to the launched MATLAB console. Run `checkBlockedInput` from the `conformance/`
folder on the MATLAB path, and separately interrupt the CLI with Ctrl+C.

Windows serial runtime and BLE/native ABI load-only compatibility checks also
passed through both wrapper and CLI compatibility entry points, separately from
behavioral conformance. No port Open, radio scan, ConnectAsync or stimulation
operation is used by those checks. Ubuntu/macOS execution remains unverified.

This is initial local implementation. See [future propagation](docs/PROPAGATION.md).
