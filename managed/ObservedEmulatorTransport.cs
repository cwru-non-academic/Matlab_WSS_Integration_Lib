using System;
using System.Threading;
using System.Threading.Tasks;
using Wss.Testing;
using Wss.Transports;

namespace Wss.Matlab.Managed
{
    /// <summary>Wraps Core's emulator with an observation gate for transient-state conformance checks.</summary>
    /// <remarks>Only explicit ConformanceMode uses this transport. Normal sends pass through unchanged.
    /// The host can briefly hold sends while observing a real pause, preventing Core's independent
    /// setup worker from completing an edit before MATLAB can observe it. No hardware is used.</remarks>
    public sealed class ObservedEmulatorTransport : ITransport, IConformanceProvider
    {
        private readonly object gate = new object();
        private readonly EmulatedWssTransport inner = new EmulatedWssTransport();
        private TaskCompletionSource<bool>? release;
        private bool disposed;

        /// <inheritdoc/>
        public bool IsConnected => inner.IsConnected;
        /// <inheritdoc/>
        public IWssConformance Conformance => inner.Conformance;
        /// <inheritdoc/>
        public event Action<byte[]> BytesReceived
        {
            add { inner.BytesReceived += value; }
            remove { inner.BytesReceived -= value; }
        }
        /// <inheritdoc/>
        public Task ConnectAsync(CancellationToken ct = default) => inner.ConnectAsync(ct);
        /// <inheritdoc/>
        public Task DisconnectAsync(CancellationToken ct = default) => inner.DisconnectAsync(ct);
        /// <inheritdoc/>
        public async Task SendAsync(byte[] data, CancellationToken ct = default)
        {
            Task? pending;
            lock (gate)
            {
                if (disposed) throw new ObjectDisposedException(nameof(ObservedEmulatorTransport));
                pending = release?.Task;
            }
            if (pending != null)
            {
                // Streaming cancellation must release an in-flight gated send so
                // Core can stop its stream task before its setup worker runs.
                var cancelled = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                using (ct.Register(() => cancelled.TrySetCanceled()))
                {
                    await Task.WhenAny(pending, cancelled.Task).ConfigureAwait(false);
                    ct.ThrowIfCancellationRequested();
                    await pending.ConfigureAwait(false);
                }
            }
            ct.ThrowIfCancellationRequested();
            await inner.SendAsync(data, ct).ConfigureAwait(false);
        }
        /// <inheritdoc/>
        public void Dispose()
        {
            lock (gate)
            {
                if (disposed) return;
                disposed = true;
                release?.TrySetResult(true);
                release = null;
            }
            inner.Dispose();
        }
        internal void BeginObservation()
        {
            lock (gate)
            {
                if (disposed) throw new ObjectDisposedException(nameof(ObservedEmulatorTransport));
                if (release != null) throw new InvalidOperationException("An emulator observation is already active.");
                release = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            }
        }
        internal void EndObservation()
        {
            lock (gate)
            {
                release?.TrySetResult(true);
                release = null;
            }
        }
    }
}
