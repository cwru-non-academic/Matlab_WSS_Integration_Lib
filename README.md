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

## Device addresses

The reusable `Config/stimConfig.json` example explicitly exposes Core's historical
`broadcastTarget` (`0x8F`) and `wssTargets` (`0x81`, `0x82`, `0x83`) defaults.
Applications supply their own config and device-specific receiver addresses; the
C# CLI example selects `0x80` for its first device. These are receiver settings.
The low-level host sender byte is not a supported Core JSON property.
Restart/reinitialize the controller after editing addresses so its client receives
the selected map.

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
run cleanup. The log path receives managed-host lifecycle/tick errors and
Core log messages without MATLAB callbacks; Core's default sink is unchanged.
`LastCoreError` exposes the latest captured Core error, which can explain failed
async connection/setup even when `Tick` did not throw. Core logging is
process-wide, so with multiple controllers an entry does not identify which
controller failed. Config controllers returned by
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

## Propagation preparation

Ordinary PR CI keeps `Integration behavioral tests` separate from the Windows,
Ubuntu and macOS compatibility checks. The same native MATLAB action is reused
by candidate preflights; it uses the production wrapper and shared Core catalog,
not MATLAB Engine or a replacement implementation.

Downloaded candidates require the exact 27-file universal inventory, including
the macOS backend and native bridge. Only the explicitly identified historical
reference copy may retain 25 files. Native evidence requires eight wrapper tests,
nine CLI tests and all ten canonical cases; normalized candidate metadata is
additional evidence and cannot replace the richer proof. Mac acceptance requires
actual packaged ABI loading, not an unsupported legacy result or a surrogate.

The prepared read-only acceptance workflow verifies a frozen Core plan, actual
human dependency merge, fresh committed-state normal CI, paired native proofs
and the CLI parent gitlink. It never creates or merges a dependency PR. Receipts
reject excluded targets, no-op/preparation-only heads and stale/missing evidence.

Approved MATLAB dev participation sets `baseline_ready` and
`candidate_preflight_ready` true and enables the pipeline contract, with effective
`WSS_MATLAB_PROPAGATION_ENABLED=true` in both MATLAB repositories. Deploy the
reviewed configuration on both main and dev. These settings permit execution;
they do not attest acceptance of a candidate or start a workflow. Every candidate
still requires immutable provenance, real native/platform preflights and reviewed
dependency merges, with `auto_merge=false`. Core automatic-trigger approval is
separate. The existing receipt verifier pin and its MATLAB exclusion are unchanged;
release acceptance needs its separately reviewed Core policy/verifier alignment.

The additional `Mac packaged BLE diagnostic (arm64)` PR job downloads the pinned
preparation artifact from Core run `40815407554`, verifies its archive hash and
27-file inventory, and tests a disposable wrapper copy with real MATLAB. It
requires successful native ABI loading, disconnected construction and CLI
selector forwarding rather than accepting the legacy unsupported result. This
job uses existing App access with read-only Core permissions; it does not change
the committed payload, connect hardware, emit acceptance receipts or activate
propagation. Its evidence applies to that preparation artifact and runner
architecture; Intel and physical BLE require separate validation.

The staged-dev receiver declaration is `.github/dev-propagation.json`. For a
verified Core producer containing `tools/ci/dev-propagation.json`, a merged
dependency PR waits for Core's all-integration barrier without requesting an
application write token. Legacy fanout is retained only when the complete tree
at that verified producer commit proves the policy is absent; API failures or
invalid policies fail closed.

Core resumes `dispatch-cli-promotion.yml` on main with `producer_run_id`,
`barrier_run_id` and `barrier_attempt`, under the title
`Resume application promotion / wss-<producer_run_id>`. Trusted Core main's
`tools/ci/dev-propagation.mjs verify-barrier` must succeed before the original
approval, parent, payload, native-evidence and application validation chain can
authorize a target-only write token. Resume uses existing App read access across
Core and all four integrations; it creates no persistent credentials or grants.

Deploy this declaration, hook and approved readiness configuration on both main
and dev before producing a staged candidate. Verify registered workflows,
rulesets and existing App access before the separately authorized Core rollout.
Keep `auto_merge` false; dependency merges and candidate validation remain required.

## Reload behavior depends on the installed Core payload

`UpdateChannelParams` writes `stim.ch.N.defaultPA`, the amplitude used by normalized stimulation, on both supported payload profiles.

With modern Core (including 2251ccb), `LoadParamsJson()` reloads all three JSON files from anchored startup defaults. A directory overload loads all three standard filenames there; an explicit calibration file uses that file with startup-default Core and model files, not its siblings. Core validates the bundle and restarts when effective Core settings change. `LoadCoreConfigFile()` delegates to Core's coordinated reload/reinitialization of all active files. It does not preserve unsaved calibration/model changes. The wrapper does not add another restart policy.

Historical Core payloads (including 76803c03 and 50afc280) only reload calibration through `LoadParamsJson`; the parameterless call uses the active calibration file. Their `LoadConfigFile` only reads Core JSON and does not rebuild the client. They do not provide modern all-JSON reload/reinitialization. A supported modern payload adoption is required for those semantics; the compatibility profile is not evidence of that adoption. `resetRadio()` remains shutdown followed by initialization from the wrapper's configured startup directory.