classdef ReloadFailureController < wss.StimulationController
    % Test-only failure injection around the real managed host and emulator.
    properties
        FailNextInitialization = false
        FailNextCleanup = false
        LastHost = []
        HostsCreated = 0
        FailNextHostConstruction = false
        UseCleanupProbe = false
        LastTransport = []
    end
    methods
        function obj = ReloadFailureController(config)
            obj@wss.StimulationController(config);
        end
    end
    methods (Access = protected)
        function transport = createTransport(obj)
            if obj.UseCleanupProbe
                transport = ReloadTransportProbe();
            else
                transport = createTransport@wss.StimulationController(obj);
            end
            obj.LastTransport = transport;
        end
        function host = createHost(obj, transport, options, snapshot)
            if obj.FailNextHostConstruction
                obj.FailNextHostConstruction = false;
                error('wss_test:HostConstructionFailure', 'Injected before host ownership transfer.');
            end
            inner = createHost@wss.StimulationController(obj, transport, options, snapshot);
            host = ReloadFailureHost(inner, obj.FailNextInitialization, obj.FailNextCleanup);
            obj.FailNextInitialization = false;
            obj.FailNextCleanup = false;
            obj.HostsCreated = obj.HostsCreated + 1;
            obj.LastHost = host;
        end
    end
end
