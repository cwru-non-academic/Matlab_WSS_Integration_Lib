function loadBleBackend(config)
%LOADBLEBACKEND Load only the selected platform's packaged Core backend.
platform = 'linux';
backend = 'WSS.Transport.BLE.Linux';
dependencies = {'Linux.Bluetooth', 'Tmds.DBus', 'Microsoft.Bcl.AsyncInterfaces', ...
    'System.Reflection.Emit', 'System.Reflection.Emit.ILGeneration', 'System.Threading.Tasks.Extensions'};
if ispc
    platform = 'windows'; backend = 'WSS.Transport.BLE.Windows';
    dependencies = {'WSS.Transport.BLE.Windows.Native'};
elseif ismac
    platform = 'macos'; backend = 'WSS.Transport.BLE.MacOS';
    dependencies = {};
end
directory = fullfile(config.CsLibDir, 'backends', platform);
for name = [dependencies, {backend}]
    assembly = fullfile(directory, [name{1} '.dll']);
    if ~isfile(assembly)
        error('wss:MissingBleBackend', 'Selected BLE backend requires the packaged assembly %s.', assembly);
    end
    NET.addAssembly(assembly);
end
if ismac
    native = fullfile(directory, 'libwss_macos_ble.dylib');
    if ~isfile(native)
        error('wss:MissingBleBackend', 'Selected macOS BLE backend requires %s.', native);
    end
    % Core's DllImport resolves the native library beside this loaded assembly.
    % Validate that lookup and ABI before any live discovery request.
    Wss.Transports.Backends.MacOS.MacBleBackend.VerifyNativeAbi();
    Wss.Transports.Backends.MacOS.MacBleBackend.Register();
end
end
