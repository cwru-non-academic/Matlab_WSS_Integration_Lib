# WSS MATLAB Integration Library

Use WSS Core from MATLAB scripts, applications and GUIs. For a ready-made console
application, use the [MATLAB CLI](https://github.com/cwru-non-academic/CLI_Matlab_WSS_Application#readme).
The [WSS documentation](https://cwru-non-academic.github.io/WSS_Documentation/)
explains the shared architecture, configuration and stimulation contracts.

## Prerequisites

- Git and a .NET SDK capable of building `netstandard2.0` projects.
- MATLAB with support for the .NET runtime selected for the bundled Core payload.
  MATLAB R2026b with .NET 8 is a working combination.
- The committed `Cs_Libraries/` payload and application configuration JSON files.
  Keep its backend and runtime subdirectories with the DLLs.

Select the CLR in a fresh MATLAB process before loading any .NET assembly.
See MathWorks' [runtime selection documentation](https://www.mathworks.com/help/matlab/ref/dotnetenv.html)
for your MATLAB release. Runtime selection can persist across sessions; the
library does not select or change it for you.

## Add to your application

From your application's Git repository:

```powershell
git submodule add https://github.com/cwru-non-academic/Matlab_WSS_Integration_Lib.git external/wss-matlab-wrapper
git submodule update --init --recursive
dotnet build external/wss-matlab-wrapper/managed/Wss.Matlab.Managed.csproj -c Release
```

Commit `.gitmodules` and the submodule revision with your application. When
cloning an existing application, use `git clone --recursive` or run
`git submodule update --init --recursive` after cloning. The managed build uses
the bundled Core DLL, so a separate Core checkout is unnecessary.

## First run without hardware

Save the following function as `wss_smoke.m` in your application root, then call
`wss_smoke` from that directory in a fresh MATLAB process. The in-memory emulator
is selected explicitly and does not open a physical transport. Function scope
ensures cleanup runs on return or error:

```matlab
function wss_smoke()
dotnetenv("core", Version="8");
wrapperRoot = fullfile(pwd, 'external', 'wss-matlab-wrapper');
addpath(fullfile(wrapperRoot, 'src'));
config = wss.WssConfig('ConformanceMode', true);
controller = wss.StimulationController(config);
cleanup = onCleanup(@() controller.Shutdown()); %#ok<NASGU>
controller.Initialize();

% Setup runs asynchronously; allow a bounded wait before using the controller.
setupTimer = tic;
while ~controller.Started() && toc(setupTimer) < 10
    pause(0.01);
end
assert(controller.Started(), 'WSS setup did not become operational.');
disp(controller.Started());
end
```

For a standalone checkout, clone this repository, build
`managed/Wss.Matlab.Managed.csproj`, and set `wrapperRoot = pwd` instead.

`TestMode=true` selects Core's simulated transport; `ConformanceMode=true`
selects the behavior-test emulator. Choose one. Without either flag, initialization
uses serial and can automatically select a port. For a deliberate serial session,
pass `'SerialPort', 'COM3'` (or your operating system's port path) and omit the
emulator flags.

## Configuration and lifecycle

Set `ConfigPath` to your application's configuration directory and `LogPath` to
its log file. Defaults use this library's `Config/` examples and a temporary log.
`CsLibDir` defaults to the library's bundled `Cs_Libraries/` directory.
See the [shared configuration reference](https://cwru-non-academic.github.io/WSS_Documentation/apiDocs/conceptual/config-files-reference.html)
before changing channel mappings, firmware mode or stimulation parameters.

Initialize once, wait for the operational state, and call `Shutdown()` when finished.
Automatic setup advances into `Started()`/streaming; `Ready()` is a separate state
and can be transient during that sequence. The example waits for `Started()`.
`onCleanup` handles normal errors and Ctrl+C unwinding; forced process termination
cannot run cleanup. The managed host ticks independently of MATLAB's execution
queue. Inspect `LastTickError` if a background operation fails; do not mutate raw
configuration controllers concurrently with ticking.

The facade includes `StartStimulation`, `StopStimulation`, `StimulateAnalog`,
`StimulateNormalized`, `StimWithMode`, parameter access and channel settings.
Core defines their units, limits and protocol semantics. Finger aliases and `chN`
identify one-based channels; target `0` broadcasts, while `1` through `3` identify devices.

## Development checks

From this repository, run managed checks without MATLAB or hardware:

```powershell
dotnet run --project tests/managed/ManagedHostChecks.csproj -c Release
```

In MATLAB after selecting the runtime and building the managed host:

```matlab
addpath('src');
assertSuccess(runtests('tests'));
addpath('conformance');
results = runConformance();
```

These exercise the emulator and managed lifecycle. For CI details, see
[ci/README.md](ci/README.md). Payload provenance is recorded in
[`Cs_Libraries/payload-source.json`](Cs_Libraries/payload-source.json).
