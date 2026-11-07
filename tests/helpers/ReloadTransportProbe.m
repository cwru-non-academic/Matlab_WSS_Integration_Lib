classdef ReloadTransportProbe < handle
    % Pre-host ownership probe; never connects and is never passed into Core.
    properties
        FailDispose = true
        Disposals = 0
    end
    methods
        function Dispose(obj)
            obj.Disposals = obj.Disposals + 1;
            if obj.FailDispose
                error('wss_test:TransportCleanupFailure', 'Injected candidate transport cleanup failure.');
            end
        end
    end
end
