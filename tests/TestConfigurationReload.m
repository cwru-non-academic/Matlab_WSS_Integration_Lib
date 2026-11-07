function tests = TestConfigurationReload
% Public MATLAB facade tests against the real in-memory Core transport.
tests = functiontests(localfunctions);
end

function testFailedInitialHostRequiresCleanup(testCase)
[root, c, oldPath] = failureController();
cleanup = onCleanup(@() releaseFailure(c, root, oldPath));
c.FailNextInitialization = true;
c.FailNextCleanup = true;
verifyError(testCase, @() c.Initialize(), 'wss_test:InitializeFailure');
verifyError(testCase, @() c.Initialize(), 'wss:CleanupPending');
verifyEqual(testCase, c.HostsCreated, 1);
c.LastHost.FailCleanup = false;
c.Shutdown();
c.Initialize(); waitStarted(c);
verifyEqual(testCase, c.HostsCreated, 2);
c.Initialize();
verifyEqual(testCase, c.HostsCreated, 2);
end

function testFailedReloadRetainsSnapshotAndRequiresRecovery(testCase)
[root, c, oldPath] = failureController();
cleanup = onCleanup(@() releaseFailure(c, root, oldPath));
c.Initialize(); waitStarted(c);
c.FailNextInitialization = true;
c.FailNextCleanup = true;
writeCore(root, 2);
verifyError(testCase, @() c.resetRadio(), 'wss_test:InitializeFailure');
verifyError(testCase, @() c.Initialize(), 'wss:ReloadPending');
verifyError(testCase, @() c.LoadParamsJson(), 'wss:ReloadPending');
verifyError(testCase, @() c.resetRadio(), 'wss:ReloadPending');
verifyFalse(testCase, c.Ready());
verifyFalse(testCase, c.Started());
verifyError(testCase, @() c.RetryReload(), 'wss_test:CleanupFailure');
verifyEqual(testCase, c.HostsCreated, 2);
writeText(fullfile(root, 'stimConfig.json'), 'invalid');
c.LastHost.FailCleanup = false;
c.RetryReload(); waitStarted(c);
verifyEqual(testCase, c.HostsCreated, 3);
verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 2);
observe(c, @() c.StimWithMode('ch2', .5), 100, 2);
end

function testConstructorFailureRetainsCandidateAndOriginalError(testCase)
[root, c, oldPath] = failureController();
cleanup = onCleanup(@() releaseFailure(c, root, oldPath));
c.UseCleanupProbe = true;
c.FailNextHostConstruction = true;
try
    c.Initialize();
    error('wss_test:ExpectedFailure', 'Host construction unexpectedly succeeded.');
catch failure
    verifyEqual(testCase, failure.identifier, 'wss_test:HostConstructionFailure');
    verifyEqual(testCase, numel(failure.cause), 1);
    verifyEqual(testCase, failure.cause{1}.identifier, 'wss_test:TransportCleanupFailure');
end
verifyEqual(testCase, c.LastTransport.Disposals, 1);
verifyError(testCase, @() c.Initialize(), 'wss:CleanupPending');
probe = c.LastTransport;
probe.FailDispose = false;
c.Shutdown();
verifyEqual(testCase, probe.Disposals, 2);
c.UseCleanupProbe = false;
c.Initialize(); waitStarted(c);
end

function testConstructorFailureDuringReloadRetainsValidatedSnapshot(testCase)
[root, c, oldPath] = failureController();
cleanup = onCleanup(@() releaseFailure(c, root, oldPath));
c.Initialize(); waitStarted(c);
writeCore(root, 2);
c.UseCleanupProbe = true;
c.FailNextHostConstruction = true;
verifyError(testCase, @() c.resetRadio(), 'wss_test:HostConstructionFailure');
verifyError(testCase, @() c.LoadParamsJson(), 'wss:ReloadPending');
verifyError(testCase, @() c.RetryReload(), 'wss_test:TransportCleanupFailure');
writeText(fullfile(root, 'stimConfig.json'), 'invalid');
c.LastTransport.FailDispose = false;
c.UseCleanupProbe = false;
c.RetryReload(); waitStarted(c);
verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 2);
observe(c, @() c.StimWithMode('ch2', .5), 100, 2);
end

function testShutdownAbandonsPendingSnapshotBeforeCleanupRetry(testCase)
[root, c, oldPath] = failureController();
cleanup = onCleanup(@() releaseFailure(c, root, oldPath));
c.Initialize(); waitStarted(c);
c.UseCleanupProbe = true;
c.FailNextHostConstruction = true;
verifyError(testCase, @() c.resetRadio(), 'wss_test:HostConstructionFailure');
verifyError(testCase, @() c.Shutdown(), 'wss_test:TransportCleanupFailure');
verifyError(testCase, @() c.RetryReload(), 'wss:NoPendingReload');
verifyError(testCase, @() c.Initialize(), 'wss:CleanupPending');
c.LastTransport.FailDispose = false;
c.Shutdown();
end

function testRetiredHostStopsTicksAndDetachesLogs(testCase)
[root, c, oldPath] = failureController();
cleanup = onCleanup(@() releaseFailure(c, root, oldPath));
c.Initialize(); waitStarted(c);
previous = c.LastHost.Inner;
Wss.CoreModule.Log.Error('before-parity-reset');
verifyEqual(testCase, char(previous.LastCoreError), 'before-parity-reset');
c.resetRadio(); waitStarted(c);
ticks = previous.TickCount;
Wss.CoreModule.Log.Error('after-parity-reset');
pause(.03);
verifyEqual(testCase, previous.TickCount, ticks);
verifyEqual(testCase, char(previous.LastCoreError), 'before-parity-reset');
verifyEqual(testCase, char(c.LastHost.Inner.LastCoreError), 'after-parity-reset');
end

function [root, c, oldPath] = failureController()
oldPath = path;
addpath(fullfile(fileparts(mfilename('fullpath')), 'helpers'));
root = tempname;
writeProfile(root, 1, 50, 150, 2, 1);
c = ReloadFailureController(wss.WssConfig('ConfigPath', root, ...
    'LogPath', fullfile(root, 'host.log'), 'ConformanceMode', true, 'TickIntervalMs', 1));
end

function releaseFailure(c, root, oldPath)
pathCleanup = onCleanup(@() path(oldPath));
if ~isempty(c.LastHost), c.LastHost.FailCleanup = false; end
if isa(c.LastTransport, 'ReloadTransportProbe'), c.LastTransport.FailDispose = false; end
release(c, root);
end

function testProfileFileDefaultsAndCoreReset(testCase)
root = tempname;
writeProfile(root, 1, 50, 150, 2, 1);
c = wss.StimulationController(wss.WssConfig('ConfigPath', root, ...
    'LogPath', fullfile(root, 'host.log'), 'ConformanceMode', true, 'TickIntervalMs', 1));
cleanup = onCleanup(@() release(c, root));
c.Initialize(); waitStarted(c);
original = c.GetConformance();
writeProfile(root, 1, 100, 200, 4, .5);
c.LoadParamsJson();
verifyTrue(testCase, System.Object.ReferenceEquals(original, c.GetConformance()));
observe(c, @() c.StimWithMode('ch2', .5), 125, 4);
c.UpdateChannelParams('ch2', 300, 100, 5);
observe(c, @() c.StimulateNormalized('ch2', .5), 200, 5);
writeProfile(root, 1, 50, 150, 2, 1);
profile = fullfile(root, 'profile with spaces');
writeProfile(profile, 2, 100, 200, 4, .5);
c.LoadParamsJson(profile); waitStarted(c);
verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 2);
verifyFalse(testCase, System.Object.ReferenceEquals(original, c.GetConformance()));
assertStopped(original);
retiredCount = original.MessageHistory.Length;
observe(c, @() c.StimWithMode('ch2', .5), 125, 4);
verifyEqual(testCase, original.MessageHistory.Length, retiredCount);
file = fullfile(profile, 'specific parameters.json');
copyfile(fullfile(profile, 'stimParams.json'), file);
c.LoadParamsJson(file); waitStarted(c);
verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 1);
observe(c, @() c.StimWithMode('ch2', .5), 150, 4);
oldDirectory = pwd;
restoreDirectory = onCleanup(@() cd(oldDirectory));
cd(profile);
c.LoadParamsJson(); waitStarted(c);
observe(c, @() c.StimWithMode('ch2', .5), 100, 2);
cd(oldDirectory);
c.LoadParamsJson(profile); waitStarted(c);
c.UpdateChannelParams('ch2', 240, 80, 6);
writeText(fullfile(profile, 'modelConfig.json'), 'invalid');
writeText(fullfile(profile, 'stimParams.json'), 'invalid');
writeCore(profile, 1);
c.LoadCoreConfigFile(); waitStarted(c);
verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 1);
observe(c, @() c.StimWithMode('ch2', .5), 120, 6);
writeCore(profile, 2);
c.resetRadio(); waitStarted(c);
verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 2);
observe(c, @() c.StimWithMode('ch2', .5), 120, 6);
end

function testInvalidBundleKeepsActiveState(testCase)
root = tempname;
writeProfile(root, 1, 50, 150, 2, 1);
c = wss.StimulationController(wss.WssConfig('ConfigPath', root, ...
    'LogPath', fullfile(root, 'host.log'), 'ConformanceMode', true, 'TickIntervalMs', 1));
cleanup = onCleanup(@() release(c, root));
c.Initialize(); waitStarted(c);
original = c.GetConformance();
writeCore(root, 2);
writeText(fullfile(root, 'modelConfig.json'), 'invalid');
failed = false;
try
    c.LoadParamsJson();
catch
    failed = true;
end
verifyTrue(testCase, failed);
verifyTrue(testCase, System.Object.ReferenceEquals(original, c.GetConformance()));
verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 1);
observe(c, @() c.StimWithMode('ch2', .5), 100, 2);
end

function observe(c, operation, pw, amplitude)
trace = c.GetConformance();
messages = trace.MessageHistory;
baseline = messages(messages.Length).SequenceNumber;
operation();
started = tic;
while toc(started) < 5
    history = trace.StimulationHistory;
    for k = 1:history.Length
        item = history(k);
        if item.SequenceNumber > baseline && item.Channel == 2 && ...
                item.PulseWidth == pw && item.PulseAmplitude == amplitude && item.InterPulseInterval == 13
            return;
        end
    end
    pause(.001);
end
error('wss:ReloadOutput', 'Requested channel 2 output was not observed.');
end

function assertStopped(trace)
history = trace.StimulationHistory;
for k = history.Length:-1:1
    item = history(k);
    if item.Channel == 2
        assert(item.PulseWidth == 0 && item.PulseAmplitude == 0, ...
            'Retired stack did not finish with zero output.');
        return;
    end
end
error('wss:MissingReloadStop', 'Retired stack did not produce channel 2 output.');
end

function waitStarted(c)
started = tic;
while toc(started) < 5
    if c.Started(), return; end
    pause(.001);
end
error('wss:ReloadStartup', 'Reload did not start.');
end

function writeProfile(directory, devices, low, high, amp, gain)
if ~isfolder(directory), mkdir(directory); end
writeCore(directory, devices);
channels = cell(1, 9);
for k = 1:9
    channels{k} = sprintf('"%d":{"ampMode":"PW","minPW":%d,"maxPW":%d,"defaultPA":%d,"IPI":13}', k, low, high, amp);
end
writeText(fullfile(directory, 'stimParams.json'), ['{"stim":{"ch":{' strjoin(channels, ',') '}}}']);
writeText(fullfile(directory, 'modelConfig.json'), sprintf('{"calib":{"mode":"P"},"constants":{"PModeProportional":%g}}', gain));
end

function writeCore(directory, devices)
writeText(fullfile(directory, 'stimConfig.json'), sprintf(['{"maxWSS":%d,"firmware":"J03",' ...
    '"useConfigAmpCurves":true,"ampCurves":[{"LowThreshold":0,"LowConst":1,' ...
    '"ExpPower":1,"LinearOffset":-1,"LinearSlope":1}]}'], devices));
end

function writeText(file, text)
f = fopen(file, 'w');
cleanup = onCleanup(@() fclose(f));
fprintf(f, '%s', text);
end

function release(c, root)
c.Shutdown();
if isfolder(root), rmdir(root, 's'); end
end
