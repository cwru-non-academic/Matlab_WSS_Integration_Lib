using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Threading;
using CoreLog = Wss.CoreModule.Log;

namespace Wss.Matlab.Managed
{
    /// <summary>Serializes controller calls and ticks the managed stack without MATLAB callbacks.</summary>
    /// <remarks>Owns the supplied stack. Dispose before unloading or replacing its assemblies.
    /// Calls and ticks share one lock; the requested interval is best effort, not a real-time guarantee.</remarks>
    public sealed class ControllerHost : IDisposable
    {
        private readonly object gate = new object();
        private readonly object logGate = new object();
        private bool captureCoreLogs;
        private string lastCoreError = "";
        private readonly object disposeGate = new object();
        private readonly object stack;
        private readonly int interval;
        private readonly string logPath;
        private readonly ManualResetEvent stop = new ManualResetEvent(false);
        private readonly MethodInfo tick;
        private Thread? thread;
        private object? basic;
        private bool initialized;
        private bool disposed;
        private Exception? tickFailure;
        private long tickCount;

        /// <summary>Creates an uninitialized host that takes ownership of a managed layer stack.</summary>
        /// <param name="stack">ModelParamsLayer or a compatible managed lifecycle object.</param>
        /// <param name="tickIntervalMs">Positive minimum delay in milliseconds between completed ticks.</param>
        /// <param name="logPath">File receiving host lifecycle and failure diagnostics.</param>
        public ControllerHost(object stack, int tickIntervalMs, string logPath)
        {
            this.stack = stack ?? throw new ArgumentNullException(nameof(stack));
            if (tickIntervalMs < 1) throw new ArgumentOutOfRangeException(nameof(tickIntervalMs));
            interval = tickIntervalMs;
            this.logPath = Path.GetFullPath(logPath);
            tick = stack.GetType().GetMethod("Tick", Type.EmptyTypes)
                ?? throw new MissingMethodException(stack.GetType().FullName, "Tick");
        }

        /// <summary>Gets whether the initialized stack exposes the optional basic API.</summary>
        public bool BasicSupported { get { lock (gate) return initialized && !disposed && basic != null; } }

        /// <summary>Gets the number of successfully completed managed ticks.</summary>
        public long TickCount => Interlocked.Read(ref tickCount);

        /// <summary>Gets the first background tick failure, or an empty string.</summary>
        public string LastTickError { get { lock (gate) return tickFailure?.ToString() ?? ""; } }

        /// <summary>Gets the latest process-wide Core error captured during this host's lifetime.</summary>
        /// <remarks>Core's logger is global: with multiple controllers, an entry is diagnostic
        /// evidence and cannot identify which controller failed. No MATLAB callback is used.</remarks>
        public string LastCoreError { get { lock (logGate) return lastCoreError; } }

        /// <summary>Initializes the stack and starts one background managed thread, once.</summary>
        /// <remarks>No delegate enters MATLAB. A failed initialization disposes the owned stack.</remarks>
        public void Initialize()
        {
            lock (gate)
            {
                ThrowIfDisposed();
                if (initialized) return;
                try
                {
                    lock (logGate) captureCoreLogs = true;
                    CoreLog.Message += OnCoreMessage;
                    Invoke(stack, "Initialize", Array.Empty<object>());
                    MethodInfo? probe = stack.GetType().GetMethods().SingleOrDefault(m =>
                        m.Name == "TryGetBasic" && m.GetParameters().Length == 1);
                    if (probe != null)
                    {
                        object[] args = { null! };
                        if ((bool)InvokeMethod(stack, probe, args)!) basic = args[0];
                    }
                    initialized = true;
                    thread = new Thread(Run) { IsBackground = true, Name = "wss-matlab-tick" };
                    thread.Start();
                    Log("Initialized");
                }
                catch
                {
                    initialized = false;
                    disposed = true;
                    CleanupStack();
                    DetachCoreLogs();
                    stop.Dispose();
                    throw;
                }
            }
        }

        /// <summary>Invokes a public stack operation, serialized with Tick.</summary>
        /// <param name="method">Exact public managed method name.</param>
        /// <param name="arguments">Arguments; scalar numeric values are converted to the declared CLR type.</param>
        /// <returns>The managed return value, or null for void.</returns>
        /// <exception cref="InvalidOperationException">The stack is uninitialized or a background tick failed.</exception>
        public object? Call(string method, object[] arguments)
        {
            lock (gate)
            {
                EnsureRunning();
                return Invoke(stack, method, arguments);
            }
        }

        /// <summary>Invokes a basic operation, failing explicitly when the capability is unavailable.</summary>
        /// <param name="method">Exact public basic method name.</param>
        /// <param name="arguments">Managed arguments.</param>
        /// <returns>The managed return value, or null for void.</returns>
        public object? CallBasic(string method, object[] arguments)
        {
            lock (gate)
            {
                EnsureRunning();
                if (basic == null) throw new NotSupportedException("Basic stimulation is unavailable.");
                return Invoke(basic, method, arguments);
            }
        }

        /// <summary>Invokes a basic operation and observes a real pause using the explicit emulator's send gate.</summary>
        /// <param name="method">Exact public basic method name.</param>
        /// <param name="arguments">Managed arguments.</param>
        /// <param name="transport">The explicit conformance emulator, with an observation gate.</param>
        /// <returns>False after a real non-Started state is observed; fails on a finite timeout.</returns>
        /// <remarks>Gating host ticks alone does not block Core's independent setup worker. The
        /// emulator holds sends and honors cancellation until the pause is observed, then resumes
        /// unchanged Core behavior. Subsequent Started calls always read current state.</remarks>
        public bool CallBasicAndReadStarted(string method, object[] arguments, ObservedEmulatorTransport transport)
        {
            lock (gate)
            {
                EnsureRunning();
                if (basic == null) throw new NotSupportedException("Basic stimulation is unavailable.");
                if (transport == null) throw new ArgumentNullException(nameof(transport));
                transport.BeginObservation();
                try
                {
                    Invoke(basic, method, arguments);
                    var deadline = System.Diagnostics.Stopwatch.StartNew();
                    while ((bool)Invoke(stack, "Started", Array.Empty<object>())!)
                    {
                        if (deadline.ElapsedMilliseconds >= 2000)
                            throw new TimeoutException("Core did not enter a paused state during the emulator observation.");
                        Thread.Sleep(1);
                    }
                    return false;
                }
                finally { transport.EndObservation(); }
            }
        }

        /// <summary>Looks up a parameter while preserving the CLR out value.</summary>
        /// <param name="key">Parameter key.</param>
        /// <returns>A two-element array containing Boolean found and Single value.</returns>
        public object[] TryGetStimParam(string key)
        {
            lock (gate)
            {
                EnsureRunning();
                MethodInfo method = stack.GetType().GetMethod("TryGetStimParam")
                    ?? throw new MissingMethodException("TryGetStimParam");
                object[] args = { key, 0f };
                return new[] { InvokeMethod(stack, method, args)!, args[1] };
            }
        }

        /// <summary>Stops ticking, requests a broadcast stop, shuts down and disposes the stack once.</summary>
        /// <remarks>Waits for an in-flight managed call/tick to return; no managed calls occur after return.
        /// Cleanup failures are logged and remaining cleanup is attempted. No hard deadline is promised.</remarks>
        public void Dispose()
        {
            lock (disposeGate)
            {
            Thread? running;
            lock (gate)
            {
                if (disposed) return;
                disposed = true;
                stop.Set();
                running = thread;
            }
            running?.Join();
            lock (gate)
            {
                CleanupStack();
                DetachCoreLogs();
                initialized = false;
                basic = null;
                thread = null;
                stop.Dispose();
                Log("Disposed");
            }
            }
        }

        private void Run()
        {
            while (!stop.WaitOne(0))
            {
                lock (gate)
                {
                    if (disposed) return;
                    try
                    {
                        InvokeMethod(stack, tick, Array.Empty<object>());
                        Interlocked.Increment(ref tickCount);
                    }
                    catch (Exception error)
                    {
                        tickFailure = error;
                        Log("Tick failed: " + error);
                        TryStop();
                        return;
                    }
                }
                if (stop.WaitOne(interval)) return;
            }
        }

        private void CleanupStack()
        {
            TryStop();
            foreach (string method in new[] { "Shutdown", "Dispose" })
            {
                try { Invoke(stack, method, Array.Empty<object>()); }
                catch (Exception error) { Log(method + " failed: " + error); }
            }
        }

        private void TryStop()
        {
            try
            {
                MethodInfo? method = stack.GetType().GetMethods().FirstOrDefault(m =>
                    m.Name == "StopStim" && m.GetParameters().Length == 1);
                if (method == null) return;
                Type targetType = method.GetParameters()[0].ParameterType;
                InvokeMethod(stack, method, new[] { Enum.Parse(targetType, "Broadcast") });
            }
            catch (Exception error) { Log("StopStim failed: " + error); }
        }

        private void ThrowIfDisposed()
        {
            if (disposed) throw new ObjectDisposedException(nameof(ControllerHost));
        }

        private void EnsureRunning()
        {
            ThrowIfDisposed();
            if (!initialized) throw new InvalidOperationException("Call Initialize first.");
            if (tickFailure != null) throw new InvalidOperationException("Managed ticking failed.", tickFailure);
        }

        private void OnCoreMessage(CoreLog.LogLevel level, string message)
        {
            lock (logGate)
            {
                if (!captureCoreLogs) return;
                if (level == CoreLog.LogLevel.Error) lastCoreError = message ?? "";
                Log("Core (process-wide) " + level + ": " + message);
            }
        }

        private void DetachCoreLogs()
        {
            CoreLog.Message -= OnCoreMessage;
            // Fence a callback already copied by Core's event publisher.
            lock (logGate) captureCoreLogs = false;
        }

        private void Log(string message)
        {
            lock (logGate)
            {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
                File.AppendAllText(logPath, DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)
                    + " " + message + Environment.NewLine);
            }
            catch { /* Diagnostics must not prevent shutdown. */ }
            }
        }

        private static object? Invoke(object receiver, string name, object[] supplied)
        {
            var matches = receiver.GetType().GetMethods(BindingFlags.Public | BindingFlags.Instance)
                .Where(m => m.Name == name && m.GetParameters().Length == supplied.Length)
                .Select(m => new { Method = m, Args = ConvertArguments(m, supplied) })
                .Where(x => x.Args != null).ToArray();
            if (matches.Length == 0) throw new MissingMethodException(receiver.GetType().FullName, name);
            if (matches.Length > 1)
            {
                var exact = matches.Where(x => x.Method.GetParameters().Select((p, i) =>
                    supplied[i] == null || p.ParameterType.IsInstanceOfType(supplied[i])).All(v => v)).ToArray();
                if (exact.Length != 1) throw new AmbiguousMatchException(name);
                return InvokeMethod(receiver, exact[0].Method, exact[0].Args!);
            }
            return InvokeMethod(receiver, matches[0].Method, matches[0].Args!);
        }

        private static object[]? ConvertArguments(MethodInfo method, object[] supplied)
        {
            var converted = new object[supplied.Length];
            ParameterInfo[] parameters = method.GetParameters();
            try
            {
                for (int i = 0; i < supplied.Length; i++)
                {
                    Type type = parameters[i].ParameterType;
                    if (type.IsByRef) return null;
                    object value = supplied[i];
                    if (value == null || type.IsInstanceOfType(value)) converted[i] = value!;
                    else if (type.IsEnum) return null;
                    else converted[i] = Convert.ChangeType(value, type, CultureInfo.InvariantCulture);
                }
            }
            catch (Exception error) when (error is InvalidCastException || error is FormatException || error is OverflowException)
            { return null; }
            return converted;
        }

        private static object? InvokeMethod(object receiver, MethodInfo method, object[] arguments)
        {
            try { return method.Invoke(receiver, arguments); }
            catch (TargetInvocationException error) when (error.InnerException != null)
            {
                ExceptionDispatchInfo.Capture(error.InnerException).Throw();
                throw;
            }
        }
    }
}
