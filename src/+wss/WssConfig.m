classdef WssConfig
    %WSSCONFIG Immutable paths and transport options for the reusable wrapper.
    properties (SetAccess = immutable)
        ConfigPath
        LogPath
        CsLibDir
        SerialPort
        Transport
        BleAutoSelect
        BleDeviceName
        BleDeviceId
        TestMode
        ConformanceMode
        MaxSetupTries
        TickIntervalMs
    end
    methods
        function obj = WssConfig(varargin)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            p = inputParser;
            p.FunctionName = 'wss.WssConfig';
            text = @(x) (ischar(x) && (isrow(x) || isempty(x))) || (isstring(x) && isscalar(x));
            flag = @(x) islogical(x) && isscalar(x);
            positiveInteger = @(x) isnumeric(x) && isscalar(x) && isreal(x) && isfinite(x) && ...
                x >= 1 && x == fix(x) && x <= double(intmax('int32'));
            addParameter(p, 'ConfigPath', fullfile(root, 'Config'), text);
            addParameter(p, 'LogPath', fullfile(tempdir, 'wss-matlab.log'), text);
            addParameter(p, 'CsLibDir', fullfile(root, 'Cs_Libraries'), text);
            addParameter(p, 'SerialPort', '', text);
            addParameter(p, 'Transport', '', text);
            addParameter(p, 'BleAutoSelect', false, flag);
            addParameter(p, 'BleDeviceName', '', text);
            addParameter(p, 'BleDeviceId', '', text);
            addParameter(p, 'TestMode', false, flag);
            addParameter(p, 'ConformanceMode', false, flag);
            addParameter(p, 'MaxSetupTries', 5, positiveInteger);
            addParameter(p, 'TickIntervalMs', 10, positiveInteger);
            parse(p, varargin{:});
            r = p.Results;
            if r.TestMode && r.ConformanceMode
                error('wss:ConflictingTransport', 'Select TestMode or ConformanceMode, not both.');
            end
            transport = lower(char(r.Transport));
            if ~isempty(transport) && ~ismember(transport, {'serial', 'ble', 'test', 'conformance'})
                error('wss:UnsupportedTransport', 'Expected serial, ble, test, or conformance.');
            end
            alias = '';
            if r.TestMode, alias = 'test'; end
            if r.ConformanceMode, alias = 'conformance'; end
            if ~isempty(alias)
                if ~isempty(transport) && ~strcmp(transport, alias)
                    error('wss:ConflictingTransport', 'Transport conflicts with TestMode or ConformanceMode.');
                end
                transport = alias;
            end
            if isempty(transport), transport = 'serial'; end
            if strcmp(transport, 'ble') && ~r.BleAutoSelect && ...
                    isempty(strtrim(char(r.BleDeviceName))) && isempty(strtrim(char(r.BleDeviceId)))
                error('wss:BleSelectorRequired', 'BLE requires BleAutoSelect, BleDeviceId, or BleDeviceName.');
            end
            obj.Transport = transport;
            obj.BleAutoSelect = r.BleAutoSelect;
            obj.BleDeviceName = char(r.BleDeviceName);
            obj.BleDeviceId = char(r.BleDeviceId);
            obj.ConfigPath = obj.absolutePath(r.ConfigPath);
            obj.LogPath = obj.absolutePath(r.LogPath);
            obj.CsLibDir = obj.absolutePath(r.CsLibDir);
            obj.SerialPort = char(r.SerialPort);
            obj.TestMode = strcmp(transport, 'test');
            obj.ConformanceMode = strcmp(transport, 'conformance');
            obj.MaxSetupTries = r.MaxSetupTries;
            obj.TickIntervalMs = r.TickIntervalMs;
        end
    end
    methods (Static, Access = private)
        function value = absolutePath(value)
            value = char(value);
            if isempty(value), error('wss:EmptyPath', 'Paths must not be empty.'); end
            if isempty(regexp(value, '^([A-Za-z]:[\\/]|[\\/]{2}|/)', 'once'))
                value = fullfile(pwd, value);
            end
        end
    end
end
