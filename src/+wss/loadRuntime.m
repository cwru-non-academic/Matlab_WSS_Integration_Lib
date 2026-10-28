function loadRuntime(config)
%LOADRUNTIME Load explicit wrapper assemblies without constructing a transport.
% Select a supported CLR before calling; this function does not change
% dotnetenv, install dependencies, or persist MATLAB path changes.
if ~isa(config, 'wss.WssConfig'), error('wss:InvalidConfig', 'Expected wss.WssConfig.'); end
loadAssemblies(config);
end
