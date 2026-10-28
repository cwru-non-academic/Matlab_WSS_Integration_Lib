function tests = TestWssConfig
tests = functiontests(localfunctions);
end

function testRejectsConflictingTransports(testCase)
verifyError(testCase, @() wss.WssConfig('TestMode', true, 'ConformanceMode', true), 'wss:ConflictingTransport');
end

function testPathsAreAnchoredBeforeWorkingDirectoryChanges(testCase)
config = wss.WssConfig('ConfigPath', 'relative-config');
verifyEqual(testCase, config.ConfigPath, fullfile(pwd, 'relative-config'));
end

function testConstructionHasNoRuntimeSideEffects(testCase)
controller = wss.StimulationController(wss.WssConfig('CsLibDir', tempname));
cleanup = onCleanup(@() controller.Shutdown());
verifyFalse(testCase, controller.Ready());
verifyFalse(testCase, controller.Started());
verifyFalse(testCase, controller.BasicSupported);
verifyEqual(testCase, controller.TickCount, 0);
controller.resetRadio();
verifyFalse(testCase, controller.Ready());
verifyEqual(testCase, controller.TickCount, 0);
verifyError(testCase, @() controller.StimWithMode('thumb', 0.5), 'wss:NotInitialized');
end
