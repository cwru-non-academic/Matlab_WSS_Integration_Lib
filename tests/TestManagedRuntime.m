function tests = TestManagedRuntime
% Real MATLAB/.NET boundary checks using only the in-memory emulator.
tests = functiontests(localfunctions);
end

function testTicksProgressDuringBusyMatlab(testCase)
directory = tempname;
mkdir(directory);
root = fileparts(fileparts(mfilename('fullpath')));
copyfile(fullfile(root, 'Config', '*.json'), directory);
config = wss.WssConfig('ConfigPath', directory, 'LogPath', fullfile(directory, 'host.log'), ...
    'ConformanceMode', true, 'TickIntervalMs', 1);
controller = wss.StimulationController(config);
cleanup = onCleanup(@() release(controller, directory));
controller.Initialize();
before = controller.TickCount;
started = tic;
while toc(started) < 0.25
    % Deliberately do not drawnow or pause: managed ticking has no MATLAB callback.
    unused = sum(1:1000); %#ok<NASGU>
end
verifyGreaterThan(testCase, controller.TickCount, before);
verifyEmpty(testCase, controller.LastTickError);
end

function testFailedAssemblyLoadCanBeCleanedUp(testCase)
controller = wss.StimulationController(wss.WssConfig('CsLibDir', tempname, 'ConformanceMode', true));
cleanup = onCleanup(@() controller.Shutdown());
verifyError(testCase, @() controller.Initialize(), 'wss:MissingCore');
verifyFalse(testCase, controller.Ready());
verifyEqual(testCase, controller.TickCount, 0);
end

function release(controller, directory)
controller.Shutdown();
if isfolder(directory), rmdir(directory, 's'); end
end
