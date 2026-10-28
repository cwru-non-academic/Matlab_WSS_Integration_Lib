function checkBlockedInput
%CHECKBLOCKEDINPUT Interactive emulator check; press Enter after one second.
% Select the supported CLR and add src/ before calling this in a MATLAB console.
root = fileparts(fileparts(mfilename('fullpath')));
directory = tempname;
mkdir(directory);
copyfile(fullfile(root, 'Config', '*.json'), directory);
controller = wss.StimulationController(wss.WssConfig('ConfigPath', directory, ...
    'LogPath', fullfile(directory, 'host.log'), 'ConformanceMode', true, 'TickIntervalMs', 1));
cleanup = onCleanup(@() release(controller, directory));
controller.Initialize();
before = controller.TickCount;
fprintf('Baseline ticks: %d. Wait at least one second before pressing Enter.\n', before);
input('Emulator input check> ', 's');
after = controller.TickCount;
assert(after > before + 10, 'Managed ticks did not progress while MATLAB input was blocked.');
fprintf('PASS blocked input: ticks %d -> %d\n', before, after);
end

function release(controller, directory)
controller.Shutdown();
if isfolder(directory), rmdir(directory, 's'); end
end
