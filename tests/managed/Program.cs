using Wss.Matlab.Managed;

string root = Path.Combine(Path.GetTempPath(), "wss-matlab-host-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try
{
    var stack = new Probe();
    var host = new ControllerHost(stack, 1, Path.Combine(root, "host.log"));
    host.Initialize(); host.Initialize();
    Check(SpinWait.SpinUntil(() => host.TickCount >= 5, 3000), "Background ticking did not progress.");
    Check(stack.Initializations == 1, "Initialize was not idempotent.");
    // All foreground calls and ticks share the same ownership boundary.
    Parallel.For(0, 100, _ => host.Call("Command", new object[] { 5.0 }));
    Check(stack.Commands == 100 && stack.Overlaps == 0, "Calls/ticks overlapped or a command was lost.");
    using var observationTransport = new ObservedEmulatorTransport();
    Check(!host.CallBasicAndReadStarted("Pause", Array.Empty<object>(), observationTransport),
        "Post-command state was not captured before the next managed tick.");
    host.Dispose(); host.Dispose();
    long completedTicks = host.TickCount;
    Thread.Sleep(25);
    Check(host.TickCount == completedTicks && stack.Stops == 1 && stack.Shutdowns == 1 && stack.Disposals == 1,
        "Dispose leaked work or duplicated lifecycle cleanup.");
    try { host.Call("Command", new object[] { 5 }); throw new Exception("Call after Dispose succeeded."); }
    catch (ObjectDisposedException) { }
    Console.WriteLine("PASS lifecycle, independent ticking, serialization and terminal cleanup");

    var broken = new Probe { FailInitialize = true };
    var failedHost = new ControllerHost(broken, 1, Path.Combine(root, "failed.log"));
    try { failedHost.Initialize(); throw new Exception("Initialize failure was swallowed."); }
    catch (InvalidOperationException error) when (error.Message == "initialize failure") { }
    failedHost.Dispose();
    Check(broken.Disposals == 1 && broken.Shutdowns == 1, "Failed initialization leaked the stack.");
    Console.WriteLine("PASS failed initialization cleanup");
    string failedLength = File.ReadAllText(Path.Combine(root, "failed.log"));
    Check(failedLength.Contains("synthetic-initialization-failure"), "Initialization Core error was not captured.");
    Wss.CoreModule.Log.Error("after-failed-initialization");
    Check(File.ReadAllText(Path.Combine(root, "failed.log")) == failedLength,
        "Failed initialization left a Core log subscription attached.");

    string diagnosticPath = Path.Combine(root, "core.log");
    var diagnosticHost = new ControllerHost(new Probe(), 1, diagnosticPath);
    diagnosticHost.Initialize();
    Check(Task.Run(() => Wss.CoreModule.Log.Error("synthetic-connect-failure")).Wait(3000),
        "Background Core logging did not complete.");
    Check(diagnosticHost.LastCoreError == "synthetic-connect-failure" &&
        File.ReadAllText(diagnosticPath).Contains("Core (process-wide) Error: synthetic-connect-failure"),
        "Core error reported without a Tick exception was not captured.");
    Check(diagnosticHost.LastTickError.Length == 0,
        "A Core diagnostic must not be presented as a thrown tick failure.");
    diagnosticHost.Dispose();
    string disposedLog = File.ReadAllText(diagnosticPath);
    Wss.CoreModule.Log.Error("after-disposal");
    Check(File.ReadAllText(diagnosticPath) == disposedLog,
        "Disposed host still received Core diagnostics.");
    Console.WriteLine("PASS background Core error capture and subscription cleanup");


    var tickBroken = new Probe { FailTick = true };
    using var failedTickHost = new ControllerHost(tickBroken, 1, Path.Combine(root, "tick.log"));
    failedTickHost.Initialize();
    Check(SpinWait.SpinUntil(() => failedTickHost.LastTickError.Length > 0, 3000), "Tick failure was not exposed.");
    Check(tickBroken.Stops > 0, "Tick failure did not attempt stop.");
    try { failedTickHost.Call("Command", new object[] { 5 }); throw new Exception("Call ignored tick failure."); }
    catch (InvalidOperationException error) when (error.InnerException?.Message == "tick failure") { }
    Console.WriteLine("PASS tick failure propagation and stop attempt");
}
finally { Directory.Delete(root, recursive: true); }

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

public enum ProbeTarget { Broadcast }

public sealed class Probe
{
    public bool FailInitialize;
    public bool FailTick;
    public int Initializations, Commands, Stops, Shutdowns, Disposals, Overlaps;
    private int entered;
    private bool started = true;
    public bool TryGetBasic(out Probe basic) { basic = this; return true; }
    public bool Started() => started;
    public void Pause() { started = false; }
    public void Initialize()
    {
        Initializations++;
        if (FailInitialize)
        {
            Wss.CoreModule.Log.Error("synthetic-initialization-failure");
            throw new InvalidOperationException("initialize failure");
        }
    }
    public void Tick()
    {
        if (FailTick) throw new InvalidOperationException("tick failure");
        Enter(); started = true; Thread.SpinWait(1000); Exit();
    }
    public void Command(int value)
    {
        if (value != 5) throw new Exception("Numeric argument conversion changed.");
        Enter(); Commands++; Thread.SpinWait(1000); Exit();
    }
    public void StopStim(ProbeTarget target) { Stops++; }
    public void Shutdown() { Shutdowns++; }
    public void Dispose() { Disposals++; }
    private void Enter() { if (Interlocked.Increment(ref entered) != 1) Interlocked.Increment(ref Overlaps); }
    private void Exit() { Interlocked.Decrement(ref entered); }
}
