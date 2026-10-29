function result = checkCompatibility(csLibDir)
%CHECKCOMPATIBILITY Load-only serial/BLE package checks, separate from behavior.
% No Initialize, Open, scan, ConnectAsync or stimulation operation is called.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1, csLibDir = fullfile(root, 'Cs_Libraries'); end
wss.loadRuntime(wss.WssConfig('CsLibDir', csLibDir));
serialOptions = Wss.Transports.SerialPortTransportOptions();
serialOptions.PortName = 'ci-load-only';
serialOptions.AutoSelectPort = false;
serial = Wss.Transports.SerialPortTransport(serialOptions);
serialCleanup = onCleanup(@() serial.Dispose());
port = System.IO.Ports.SerialPort();
portCleanup = onCleanup(@() port.Dispose());
runtime = 'unix';
if ispc, runtime = 'win'; end
actualPorts = char(port.GetType().Assembly.Location);
expectedPorts = fullfile(csLibDir, 'runtimes', runtime, 'lib', 'net8.0', 'System.IO.Ports.dll');
assert(strcmpi(char(System.IO.Path.GetFullPath(actualPorts)), char(System.IO.Path.GetFullPath(expectedPorts))), ...
    'Ports assembly did not load from the selected payload runtime.');
assert(port.GetType().Assembly.GetName().Version.Major == 8, 'Expected System.IO.Ports major version 8.');
assert(~port.IsOpen, 'Load-only check must never open a serial port.');
result = struct('Serial', 'passed', 'Ble', '', 'Platform', computer);
if ismac && ~isfile(fullfile(csLibDir, 'backends', 'macos', 'WSS.Transport.BLE.MacOS.dll'))
    result.Ble = 'unsupported-by-legacy-payload';
    fprintf('Serial runtime: PASS; BLE: unavailable in the committed legacy payload.\n');
    return;
end
platform = 'linux'; backendName = 'WSS.Transport.BLE.Linux';
dependencies = {'Linux.Bluetooth', 'Tmds.DBus', 'Microsoft.Bcl.AsyncInterfaces', ...
    'System.Reflection.Emit', 'System.Reflection.Emit.ILGeneration', 'System.Threading.Tasks.Extensions'};
if ispc
    platform = 'windows'; backendName = 'WSS.Transport.BLE.Windows';
    dependencies = {'WSS.Transport.BLE.Windows.Native'};
elseif ismac
    platform = 'macos'; backendName = 'WSS.Transport.BLE.MacOS';
    dependencies = {};
end
backendDir = fullfile(csLibDir, 'backends', platform);
for k = 1:numel(dependencies)
    NET.addAssembly(fullfile(backendDir, [dependencies{k} '.dll']));
end
NET.addAssembly(fullfile(backendDir, [backendName '.dll']));
if ismac
    Wss.Transports.Backends.MacOS.MacBleBackend.Register();
    % Loads/frees the native ABI context; Core explicitly does not initialize
    % Bluetooth or request permission here. No probe/scan/connect is called.
    Wss.Transports.Backends.MacOS.MacBleBackend.VerifyNativeAbi();
end
transport = Wss.Transports.BleNusTransport('ci-load-only');
bleCleanup = onCleanup(@() transport.Dispose());
assert(~transport.IsConnected, 'Load-only check must never connect to a BLE device.');
% Native production ABI loading has no connect or radio operation.
if ispc
    native = System.Runtime.InteropServices.NativeLibrary.Load(fullfile(backendDir, 'WssBleWindows.dll'));
    nativeCleanup = onCleanup(@() System.Runtime.InteropServices.NativeLibrary.Free(native));
    exports = {'wss_ble_get_abi_info', 'wss_ble_nus_connect', 'wss_ble_nus_write', 'wss_ble_nus_disconnect'};
    for k = 1:numel(exports)
        address = System.Runtime.InteropServices.NativeLibrary.GetExport(native, exports{k});
        assert(address.ToInt64() ~= 0, 'Missing production BLE native export.');
    end
    [hasTestMode, ~] = System.Runtime.InteropServices.NativeLibrary.TryGetExport(native, 'wss_test_mode');
    assert(~hasTestMode, 'Distributed BLE DLL must not be the test shim.');
end
if ismac
    native = System.Runtime.InteropServices.NativeLibrary.Load(fullfile(backendDir, 'libwss_macos_ble.dylib'));
    nativeCleanup = onCleanup(@() System.Runtime.InteropServices.NativeLibrary.Free(native));
    exports = {'wss_mac_abi', 'wss_mac_create', 'wss_mac_destroy', 'wss_mac_submit', 'wss_mac_cancel'};
    for k = 1:numel(exports)
        address = System.Runtime.InteropServices.NativeLibrary.GetExport(native, exports{k});
        assert(address.ToInt64() ~= 0, 'Missing production macOS BLE native export.');
    end
end
% NET.addAssembly resolves the selected file; expose it in evidence.
result.Ble = 'passed';
result.Backend = backendName;
result.PortsAssembly = actualPorts;
fprintf('Serial runtime: PASS; BLE backend load-only: PASS (%s).\n', backendName);
end
