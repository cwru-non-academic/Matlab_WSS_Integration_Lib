classdef ReloadFailureHost < handle
    % Test adapter retains a real managed host; no simulated runtime results.
    properties
        Inner
        FailInitialize
        FailCleanup
    end
    methods
        function obj = ReloadFailureHost(inner, failInitialize, failCleanup)
            obj.Inner = inner;
            obj.FailInitialize = failInitialize;
            obj.FailCleanup = failCleanup;
        end
        function Initialize(obj)
            obj.Inner.Initialize();
            if obj.FailInitialize
                error('wss_test:InitializeFailure', 'Injected failure after managed initialization.');
            end
        end
        function Dispose(obj)
            if obj.FailCleanup, error('wss_test:CleanupFailure', 'Injected cleanup failure.'); end
            obj.Inner.Dispose();
        end
        function result = Call(obj, method, args), result = obj.Inner.Call(method, args); end
        function result = StageCore(obj), result = obj.Inner.StageCore(); end
    end
end
