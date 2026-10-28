function loadAssemblies(config)
%LOADASSEMBLIES Load the explicit, modern Core payload and built managed host.
% The caller selects the .NET runtime before this function; no persistent
% dotnetenv or MATLAB path settings are changed by the library.
if ~NET.isNETSupported
    error('wss:DotNetUnavailable', 'A MATLAB-supported .NET runtime is required.');
end
files = dir(fullfile(config.CsLibDir, '*.dll'));
primary = strcmpi({files.name}, 'WSS_Core_Interface.dll');
if ~any(primary)
    error('wss:MissingCore', 'Missing WSS_Core_Interface.dll in %s.', config.CsLibDir);
end
% Do not recursively load backend/native DLLs or other runtimes into one CLR.
files = [files(~primary); files(primary)];
for k = 1:numel(files)
    assembly = fullfile(files(k).folder, files(k).name);
    if strcmpi(files(k).name, 'System.IO.Ports.dll') && System.Environment.Version.Major >= 6
        platform = 'unix';
        if ispc, platform = 'win'; end
        assembly = fullfile(config.CsLibDir, 'runtimes', platform, 'lib', 'net8.0', files(k).name);
        if ~isfile(assembly)
            error('wss:MissingRuntimeAssembly', 'Missing platform System.IO.Ports runtime: %s.', assembly);
        end
    end
    NET.addAssembly(assembly);
end
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
host = fullfile(root, 'managed', 'bin', 'Release', 'netstandard2.0', 'Wss.Matlab.Managed.dll');
if ~isfile(host)
    error('wss:MissingHost', 'Build the managed host first: dotnet build "%s" -c Release', ...
        fullfile(root, 'managed', 'Wss.Matlab.Managed.csproj'));
end
NET.addAssembly(host);
end
