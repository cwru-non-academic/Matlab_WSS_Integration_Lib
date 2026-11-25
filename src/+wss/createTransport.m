function transport = createTransport(config)
%CREATETRANSPORT Construct the selected Core transport without opening hardware.
% The caller owns Dispose until passing the transport to a Core controller.
% Select a supported .NET runtime first. No scan/connect occurs here.
if ~isa(config, 'wss.WssConfig'), error('wss:InvalidConfig', 'Expected wss.WssConfig.'); end
loadAssemblies(config);
switch config.Transport
    case 'conformance'
        transport = Wss.Matlab.Managed.ObservedEmulatorTransport();
    case 'test'
        transport = Wss.Transports.TestModeTransport(Wss.Transports.TestModeTransportOptions());
    case 'ble'
        loadBleBackend(config);
        options = Wss.Transports.BleNusTransportOptions();
        options.AutoSelectDevice = config.BleAutoSelect;
        options.DeviceName = config.BleDeviceName;
        options.DeviceId = config.BleDeviceId;
        transport = Wss.Transports.BleNusTransport(options);
    otherwise
        loadLinuxSerialNative(config.CsLibDir);
        options = Wss.Transports.SerialPortTransportOptions();
        options.PortName = config.SerialPort;
        options.AutoSelectPort = isempty(config.SerialPort);
        transport = Wss.Transports.SerialPortTransport(options);
end
end

function loadLinuxSerialNative(csLibDir)
% MATLAB hosts .NET without the package's runtime asset probing paths.
% Keep the native module loaded for the lifetime of the managed Ports calls.
if ~strcmp(computer, 'GLNXA64'), return; end
persistent loadedPaths
if isempty(loadedPaths), loadedPaths = {}; end
native = fullfile(csLibDir, 'runtimes', 'linux-x64', 'native', 'libSystem.IO.Ports.Native.so');
if any(strcmp(loadedPaths, native)), return; end
if ~isfile(native)
    error('wss:MissingSerialRuntime', 'Selected Linux serial transport requires %s.', native);
end
System.Runtime.InteropServices.NativeLibrary.Load(native);
loadedPaths{end+1} = native;
end
