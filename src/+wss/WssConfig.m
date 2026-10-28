classdef WssConfig
    %WSSCONFIG Immutable paths and transport options for the reusable wrapper.
    properties (SetAccess = immutable)
        ConfigPath
        LogPath
        CsLibDir
        SerialPort
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
            addParameter(p, 'TestMode', false, flag);
            addParameter(p, 'ConformanceMode', false, flag);
            addParameter(p, 'MaxSetupTries', 5, positiveInteger);
            addParameter(p, 'TickIntervalMs', 10, positiveInteger);
            parse(p, varargin{:});
            r = p.Results;
            if r.TestMode && r.ConformanceMode
                error('wss:ConflictingTransport', 'Select TestMode or ConformanceMode, not both.');
            end
            obj.ConfigPath = obj.absolutePath(r.ConfigPath);
            obj.LogPath = obj.absolutePath(r.LogPath);
            obj.CsLibDir = obj.absolutePath(r.CsLibDir);
            obj.SerialPort = char(r.SerialPort);
            obj.TestMode = r.TestMode;
            obj.ConformanceMode = r.ConformanceMode;
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
