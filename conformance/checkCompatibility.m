function result = checkCompatibility(csLibDir)
%CHECKCOMPATIBILITY Load-only serial/BLE package checks, separate from behavior.
% No Initialize, Open, scan, ConnectAsync or stimulation operation is called.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1, csLibDir = fullfile(root, 'Cs_Libraries'); end
wss.loadRuntime(wss.WssConfig('CsLibDir', csLibDir));
serial = wss.createTransport(wss.WssConfig('CsLibDir', csLibDir, 'SerialPort', 'ci-load-only'));
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
if ispc
    platform = 'windows'; backendName = 'WSS.Transport.BLE.Windows';
elseif ismac
    platform = 'macos'; backendName = 'WSS.Transport.BLE.MacOS';
end
backendDir = fullfile(csLibDir, 'backends', platform);
transport = wss.createTransport(wss.WssConfig('CsLibDir', csLibDir, ...
    'Transport', 'ble', 'BleDeviceName', 'ci-load-only'));
bleCleanup = onCleanup(@() transport.Dispose());
assert(~transport.IsConnected, 'Load-only check must never connect to a BLE device.');
if ismac, Wss.Transports.Backends.MacOS.MacBleBackend.VerifyNativeAbi(); end
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
