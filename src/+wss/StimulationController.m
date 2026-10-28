classdef StimulationController < handle
    %STIMULATIONCONTROLLER Reusable MATLAB facade over Core/params/model layers.
    % Initialize before commands; Shutdown/delete releases the managed tick host.
    % No MATLAB timer, CLI, savepath, or physical transport is started on construction.
    properties (SetAccess = private)
        Config
    end
    properties (Dependent, SetAccess = private)
        BasicSupported
        TickCount
        LastTickError
    end
    properties (Access = private)
        Host = []
        Transport = []
    end
    methods
        function obj = StimulationController(config)
            if ~isa(config, 'wss.WssConfig')
                error('wss:InvalidConfig', 'Expected wss.WssConfig.');
            end
            obj.Config = config;
        end
        function Initialize(obj)
            if ~isempty(obj.Host), return; end
            loadAssemblies(obj.Config);
            owned = [];
            host = [];
            try
                c = obj.Config;
                if c.ConformanceMode
                    transport = Wss.Matlab.Managed.ObservedEmulatorTransport();
                elseif c.TestMode
                    transport = Wss.Transports.TestModeTransport(Wss.Transports.TestModeTransportOptions());
                else
                    options = Wss.Transports.SerialPortTransportOptions();
                    options.PortName = c.SerialPort;
                    options.AutoSelectPort = isempty(c.SerialPort);
                    transport = Wss.Transports.SerialPortTransport(options);
                end
                owned = transport;
                options = Wss.CoreModule.WssStimulationCoreOptions();
                options.ConfigPath = c.ConfigPath;
                options.MaxSetupTries = int32(c.MaxSetupTries);
                owned = Wss.CoreModule.WssStimulationCore(transport, options);
                owned = Wss.CalibrationModule.StimParamsLayer(owned, c.ConfigPath);
                owned = Wss.ModelModule.ModelParamsLayer(owned, c.ConfigPath);
                host = Wss.Matlab.Managed.ControllerHost(owned, int32(c.TickIntervalMs), c.LogPath);
                host.Initialize();
                obj.Transport = transport;
                obj.Host = host;
            catch failure
                if ~isempty(host)
                    host.Dispose();
                elseif ~isempty(owned)
                    owned.Dispose();
                end
                rethrow(failure);
            end
        end
        function Shutdown(obj)
            host = obj.Host;
            obj.Host = [];
            obj.Transport = [];
            if ~isempty(host), host.Dispose(); end
        end
        function delete(obj), obj.Shutdown(); end
        function releaseRadio(obj), obj.Shutdown(); end
        function resetRadio(obj)
            if isempty(obj.Host), return; end
            obj.Shutdown(); obj.Initialize();
        end
        function value = get.BasicSupported(obj)
            value = ~isempty(obj.Host) && logical(obj.Host.BasicSupported);
        end
        function value = get.TickCount(obj)
            value = 0;
            if ~isempty(obj.Host), value = double(obj.Host.TickCount); end
        end
        function value = get.LastTickError(obj)
            value = '';
            if ~isempty(obj.Host), value = char(obj.Host.LastTickError); end
        end
        function value = Ready(obj)
            value = ~isempty(obj.Host) && logical(obj.call('Ready'));
        end
        function value = Started(obj)
            value = ~isempty(obj.Host) && logical(obj.call('Started'));
        end
        function value = isModeValid(obj), value = logical(obj.call('IsModeValid')); end
        function StartStimulation(obj), obj.call('StartStim', obj.target(0)); end
        function StopStimulation(obj, target)
            if nargin < 2, target = 0; end
            obj.call('StopStim', obj.target(target));
        end
        function StimulateAnalog(obj, finger, pw, amp, ipi)
            if nargin < 4, amp = 3; end
            if nargin < 5, ipi = 10; end
            obj.integer(pw); obj.integer(amp); obj.integer(ipi);
            obj.call('StimulateAnalog', obj.channel(finger), int32(pw), int32(amp), int32(ipi));
        end
        function StimulateNormalized(obj, finger, magnitude)
            obj.finiteScalar(magnitude);
            obj.call('StimulateNormalized', obj.channel(finger), single(magnitude));
        end
        function StimWithMode(obj, finger, magnitude)
            obj.finiteScalar(magnitude);
            obj.call('StimWithMode', obj.channel(finger), single(magnitude));
        end
        function value = GetStimIntensity(obj, finger)
            value = double(obj.call('GetStimIntensity', obj.channel(finger)));
        end
        function SaveParamsJson(obj), obj.call('SaveParamsJson'); end
        function LoadParamsJson(obj, varargin), obj.call('LoadParamsJson', varargin{:}); end
        function LoadCoreConfigFile(obj), obj.call('LoadConfigFile'); end
        function AddOrUpdateStimParam(obj, key, value)
            obj.finiteScalar(value);
            obj.call('AddOrUpdateStimParam', char(key), single(value));
        end
        function value = GetStimParam(obj, key), value = double(obj.call('GetStimParam', char(key))); end
        function [found, value] = TryGetStimParam(obj, key)
            obj.requireHost();
            pair = obj.Host.TryGetStimParam(char(key));
            found = logical(pair(1)); value = double(pair(2));
        end
        function value = GetAllStimParams(obj), value = obj.call('GetAllStimParams'); end
        function value = GetModelConfigCTRL(obj), value = obj.call('GetModelConfigController'); end
        function value = GetCoreConfigCTRL(obj), value = obj.call('GetCoreConfigController'); end
        function value = IsFingerValid(obj, finger)
            value = logical(obj.call('IsChannelInRange', obj.channel(finger)));
        end
        function UpdateChannelParams(obj, finger, maxValue, minValue, amp)
            if ~obj.IsFingerValid(finger), error('wss:ChannelRange', 'Channel is outside current configuration.'); end
            base = sprintf('stim.ch.%d.', obj.channel(finger));
            obj.AddOrUpdateStimParam([base 'maxPW'], maxValue);
            obj.AddOrUpdateStimParam([base 'minPW'], minValue);
            obj.AddOrUpdateStimParam([base 'amp'], amp);
        end
        function SetChannelAmp(obj, finger, value)
            obj.finiteScalar(value);
            obj.call('SetChannelAmp', obj.channel(finger), single(value));
        end
        function value = GetChannelAmp(obj, finger)
            value = double(obj.call('GetChannelAmp', obj.channel(finger)));
        end
        function SetChannelPAMin(obj, finger, value)
            obj.finiteScalar(value);
            obj.call('SetChannelPAMin', obj.channel(finger), single(value));
        end
        function value = GetChannelPAMin(obj, finger)
            value = double(obj.call('GetChannelPAMin', obj.channel(finger)));
        end
        function SetChannelPAMax(obj, finger, value)
            obj.finiteScalar(value);
            obj.call('SetChannelPAMax', obj.channel(finger), single(value));
        end
        function value = GetChannelPAMax(obj, finger)
            value = double(obj.call('GetChannelPAMax', obj.channel(finger)));
        end
        function SetChannelMin(obj, finger, value)
            obj.finiteScalar(value);
            obj.call('SetChannelMin', obj.channel(finger), single(value));
        end
        function value = GetChannelMin(obj, finger)
            value = double(obj.call('GetChannelMin', obj.channel(finger)));
        end
        function SetChannelMax(obj, finger, value)
            obj.finiteScalar(value);
            obj.call('SetChannelMax', obj.channel(finger), single(value));
        end
        function value = GetChannelMax(obj, finger)
            value = double(obj.call('GetChannelMax', obj.channel(finger)));
        end
        function SetChannelPWMin(obj, finger, value)
            obj.integer(value);
            obj.call('SetChannelPWMin', obj.channel(finger), int32(value));
        end
        function value = GetChannelPWMin(obj, finger)
            value = double(obj.call('GetChannelPWMin', obj.channel(finger)));
        end
        function SetChannelPWMax(obj, finger, value)
            obj.integer(value);
            obj.call('SetChannelPWMax', obj.channel(finger), int32(value));
        end
        function value = GetChannelPWMax(obj, finger)
            value = double(obj.call('GetChannelPWMax', obj.channel(finger)));
        end
        function SetChannelDefaultPW(obj, finger, value)
            obj.integer(value);
            obj.call('SetChannelDefaultPW', obj.channel(finger), int32(value));
        end
        function value = GetChannelDefaultPW(obj, finger)
            value = double(obj.call('GetChannelDefaultPW', obj.channel(finger)));
        end
        function SetChannelIPI(obj, finger, value)
            obj.integer(value);
            obj.call('SetChannelIPI', obj.channel(finger), int32(value));
        end
        function value = GetChannelIPI(obj, finger)
            value = double(obj.call('GetChannelIPI', obj.channel(finger)));
        end
        function paused = UpdateEventRatio(obj, target, ratio, eventId)
            % An optional output observes Core's real pause using the emulator gate.
            obj.integer(ratio); obj.integer(eventId);
            obj.requireHost();
            args = obj.netArguments({int32(ratio), int32(eventId), obj.target(target)});
            if nargout == 0
                obj.Host.CallBasic('UpdateEventRatio', args);
                return;
            end
            if ~obj.Config.ConformanceMode
                error('wss:PauseObservationRequiresEmulator', 'Pause-state observation requires explicit ConformanceMode.');
            end
            paused = ~logical(obj.Host.CallBasicAndReadStarted('UpdateEventRatio', args, obj.Transport));
        end
        function Save(obj, target)
            if nargin < 2, target = 0; end
            obj.basic('Save', obj.target(target));
        end
        function load(obj, target)
            if nargin < 2, target = 0; end
            obj.basic('Load', obj.target(target));
        end
        function request_Configs(obj, target, command, id)
            obj.integer(command); obj.integer(id);
            obj.basic('Request_Configs', int32(command), int32(id), obj.target(target));
        end
        function loadWaveform(obj, filename, eventId)
            obj.integer(eventId); obj.basic('LoadWaveform', char(filename), int32(eventId));
        end
        function WaveformSetup(obj, wave, eventId, target)
            if nargin < 4, target = 0; end
            obj.integer(eventId); obj.basic('WaveformSetup', wave, int32(eventId), obj.target(target));
        end
        function UpdateIPD(obj, ipd, eventId, target)
            if nargin < 4, target = 0; end
            obj.integer(ipd); obj.integer(eventId);
            obj.basic('UpdateIPD', int32(ipd), int32(eventId), obj.target(target));
        end
        function updateWaveform(obj, varargin)
            n = numel(varargin);
            if n == 2
                obj.basic('UpdateWaveform', obj.waveform(varargin{1}), int32(varargin{2}), obj.target(0));
            elseif n == 3 && isnumeric(varargin{2}) && isscalar(varargin{2})
                obj.basic('UpdateEventShape', int32(varargin{1}), int32(varargin{2}), int32(varargin{3}), obj.target(0));
            elseif n == 3
                obj.basic('UpdateWaveform', obj.waveform(varargin{2}), int32(varargin{3}), obj.target(varargin{1}));
            elseif n == 4
                obj.basic('UpdateEventShape', int32(varargin{2}), int32(varargin{3}), int32(varargin{4}), obj.target(varargin{1}));
            else
                error('wss:WaveformSignature', 'Unsupported updateWaveform signature.');
            end
        end
        function value = GetConformance(obj)
            value = [];
            if obj.Config.ConformanceMode && ~isempty(obj.Transport)
                value = obj.Transport.Conformance;
            end
        end
    end
    methods (Access = private)
        function requireHost(obj)
            if isempty(obj.Host), error('wss:NotInitialized', 'Call Initialize before using the controller.'); end
        end
        function value = call(obj, method, varargin)
            obj.requireHost();
            value = obj.Host.Call(method, obj.netArguments(varargin));
        end
        function value = basic(obj, method, varargin)
            obj.requireHost();
            value = obj.Host.CallBasic(method, obj.netArguments(varargin));
        end
    end
    methods (Static, Access = private)
        function value = waveform(value)
            if isnumeric(value)
                validateattributes(value, {'numeric'}, {'vector', 'integer', 'finite', ...
                    '>=', double(intmin('int32')), '<=', double(intmax('int32'))});
                result = NET.createArray('System.Int32', numel(value));
                for k = 1:numel(value), result(k) = int32(value(k)); end
                value = result;
            end
        end
        function args = netArguments(values)
            args = NET.createArray('System.Object', numel(values));
            for k = 1:numel(values)
                value = values{k};
                if isstring(value), value = char(value); end
                args(k) = value;
            end
        end
        function value = target(index)
            validateattributes(index, {'numeric'}, {'scalar', 'integer', '>=', 0, '<=', 3});
            switch index
                case 0, value = Wss.CoreModule.WssTarget.Broadcast;
                case 1, value = Wss.CoreModule.WssTarget.Wss1;
                case 2, value = Wss.CoreModule.WssTarget.Wss2;
                case 3, value = Wss.CoreModule.WssTarget.Wss3;
            end
        end
        function value = channel(finger)
            text = lower(char(finger));
            names = {'thumb', 'index', 'middle', 'ring', 'pinky'};
            if strcmp(text, 'little'), text = 'pinky'; end
            index = find(strcmp(names, text), 1);
            if isempty(index) && ~isempty(regexp(text, '^ch[1-9][0-9]*$', 'once'))
                index = str2double(text(3:end));
            end
            if isempty(index) || ~isfinite(index) || index > double(intmax('int32'))
                error('wss:InvalidChannel', 'Use thumb/index/middle/ring/pinky or chN with N >= 1.');
            end
            value = int32(index);
        end
        function integer(value)
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'finite', '>=', double(intmin('int32')), '<=', double(intmax('int32'))});
        end
        function finiteScalar(value), validateattributes(value, {'numeric'}, {'scalar', 'finite', 'real'}); end
    end
end
