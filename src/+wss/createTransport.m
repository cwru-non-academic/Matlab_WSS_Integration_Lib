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
        options = Wss.Transports.SerialPortTransportOptions();
        options.PortName = config.SerialPort;
        options.AutoSelectPort = isempty(config.SerialPort);
        transport = Wss.Transports.SerialPortTransport(options);
end
end
