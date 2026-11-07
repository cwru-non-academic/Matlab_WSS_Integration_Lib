using System.Text.Json;
using Wss.CoreModule;
using Wss.Matlab.Managed;

internal static class ReloadChecks
{
    internal static void Run(string root)
    {
        string directory = Path.Combine(root, "reload");
        WriteProfile(directory, 1, 2, 1);
        var rejectedTransport = new FailingCleanupTransport();
        try
        {
            _ = new ControllerHost(rejectedTransport, new WssStimulationCoreOptions(),
                WssConfigurationSnapshot.ReadDefaults(directory), 0, Path.Combine(root, "invalid.log"));
            throw new Exception("Invalid host interval accepted.");
        }
        catch (ArgumentOutOfRangeException) { }
        if (rejectedTransport.Disposals != 0) throw new Exception("Constructor took ownership before validating arguments.");
        var failedHost = new ControllerHost(rejectedTransport, new WssStimulationCoreOptions { ConfigPath = "" },
            WssConfigurationSnapshot.ReadDefaults(directory), 1, Path.Combine(root, "build-failure.log"));
        try { failedHost.Initialize(); throw new Exception("Invalid Core construction succeeded."); }
        catch (AggregateException error) when (error.InnerExceptions.Count == 2) { }
        try { failedHost.Dispose(); throw new Exception("Candidate cleanup failure was swallowed."); }
        catch (InvalidOperationException error) when (error.Message == "transport cleanup failure") { }
        try { failedHost.Initialize(); throw new Exception("Unclean candidate allowed reconstruction."); }
        catch (ObjectDisposedException) { }
        rejectedTransport.FailDispose = false;
        failedHost.Dispose();
        if (rejectedTransport.Disposals < 3) throw new Exception("Unpublished transport was not retained for cleanup retry.");
        Console.WriteLine("PASS validated host constructor and unpublished transport cleanup fence");
        var transport = new ObservedEmulatorTransport();
        var host = new ControllerHost(transport, new WssStimulationCoreOptions { ConfigPath = directory },
            WssConfigurationSnapshot.ReadDefaults(directory), 1, Path.Combine(root, "reload.log"));
        try
        {
            host.Initialize();
            Await(() => (bool)host.Call("Started", Array.Empty<object>())!);
            foreach (string file in new[] { "stimConfig.json", "stimParams.json", "modelConfig.json" })
            {
                string path = Path.Combine(directory, file), valid = File.ReadAllText(path);
                File.WriteAllText(path, "invalid");
                try { host.StageDefaults(); throw new Exception("Invalid " + file + " was accepted."); }
                catch (InvalidDataException) { }
                File.WriteAllText(path, valid);
                Observe(host, transport, 100, 2);
            }
            WriteProfile(directory, 1, 4, .5);
            if (!host.TryApply(host.StageDefaults())) throw new Exception("Same Core requested reconstruction.");
            Observe(host, transport, 75, 4);
            WriteProfile(directory, 2, 6, .5);
            var staged = host.StageDefaults();
            if (host.TryApply(staged)) throw new Exception("Changed Core installed without reconstruction.");
            // Mutate every source after validation: construction must consume the staged copy.
            foreach (string file in new[] { "stimConfig.json", "stimParams.json", "modelConfig.json" })
                File.WriteAllText(Path.Combine(directory, file), "invalid");
            host.Dispose();
            long retiredCount = transport.Conformance.MessageHistory.Count;
            var replacementTransport = new ObservedEmulatorTransport();
            host = new ControllerHost(replacementTransport, new WssStimulationCoreOptions { ConfigPath = directory },
                staged, 1, Path.Combine(root, "replacement.log"));
            host.Initialize();
            Await(() => (bool)host.Call("Started", Array.Empty<object>())!);
            if (((CoreConfigController)host.Call("GetCoreConfigController", Array.Empty<object>())!).MaxWss != 2)
                throw new Exception("Reconstruction lost staged Core.");
            Observe(host, replacementTransport, 75, 6);
            if (transport.Conformance.MessageHistory.Count != retiredCount) throw new Exception("Retired stack continued transmitting.");
            Console.WriteLine("PASS all-layer validation, same-Core apply and immutable staged reconstruction");
        }
        finally { host.Dispose(); }
    }

    private static void Observe(ControllerHost host, ObservedEmulatorTransport transport, int pw, int amp)
    {
        long baseline = transport.Conformance.MessageHistory.Last().SequenceNumber;
        host.Call("StimWithMode", new object[] { 2, .5f });
        Await(() => transport.Conformance.StimulationHistory.Any(x => x.SequenceNumber > baseline &&
            x.Channel == 2 && x.PulseWidth == pw && x.PulseAmplitude == amp && x.InterPulseInterval == 13));
    }

    private static void Await(Func<bool> condition)
    {
        if (!SpinWait.SpinUntil(condition, 5000)) throw new Exception("Requested emulator state/output was not observed.");
    }

    private static void WriteProfile(string directory, int devices, int amp, double gain)
    {
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "stimConfig.json"), JsonSerializer.Serialize(new
        { maxWSS = devices, firmware = "J03", useConfigAmpCurves = true,
            ampCurves = new[] { new { LowThreshold = 0, LowConst = 1, ExpPower = 1, LinearOffset = -1, LinearSlope = 1 } } }));
        var channels = Enumerable.Range(1, 9).ToDictionary(x => x.ToString(), _ => new
        { ampMode = "PW", minPW = 50, maxPW = 150, defaultPA = amp, IPI = 13 });
        File.WriteAllText(Path.Combine(directory, "stimParams.json"), JsonSerializer.Serialize(new { stim = new { ch = channels } }));
        File.WriteAllText(Path.Combine(directory, "modelConfig.json"), JsonSerializer.Serialize(new
        { calib = new { mode = "P" }, constants = new { PModeProportional = gain } }));
    }
}

internal sealed class FailingCleanupTransport : Wss.Transports.ITransport
{
    public bool FailDispose = true;
    public int Disposals;
    public bool IsConnected => false;
    public event Action<byte[]> BytesReceived { add { } remove { } }
    public Task ConnectAsync(CancellationToken ct = default) => Task.CompletedTask;
    public Task DisconnectAsync(CancellationToken ct = default) => Task.CompletedTask;
    public Task SendAsync(byte[] data, CancellationToken ct = default) => Task.CompletedTask;
    public void Dispose()
    {
        Disposals++;
        if (FailDispose) throw new InvalidOperationException("transport cleanup failure");
    }
}
