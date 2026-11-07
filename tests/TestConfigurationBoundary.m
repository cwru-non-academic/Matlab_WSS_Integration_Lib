function tests = TestConfigurationBoundary
% Public wrapper boundary; real Core and emulator, no physical transport.
tests = functiontests(localfunctions);
end

function testDefaultAmplitudeReachesNormalizedOutput(testCase)
[root, c] = fixture();
cleanup = onCleanup(@() release(c, root));
c.Initialize(); waitStarted(c);
c.UpdateChannelParams('ch2', 150, 50, 6);
verifyEqual(testCase, c.GetStimParam('stim.ch.2.defaultPA'), 6);
observe(c, @() c.StimulateNormalized('ch2', .5), 100, 6);
end

function testReloadPathsAndCoreBoundary(testCase)
[root, c] = fixture();
cleanup = onCleanup(@() release(c, root));
c.Initialize(); waitStarted(c);
modern = ~isempty(c.GetCoreConfigCTRL().GetType().Assembly.GetType('Wss.CoreModule.WssConfigurationSnapshot'));
original = c.GetConformance();
initialSetups = setupCount(c);
verifyGreaterThan(testCase, initialSetups, 0);
writeProfile(root, 1, 4, .5);
reload(c, 'params');
if modern
    observe(c, @() stimulate(c, modern), 75, 4);
else
    % Historical Core reloads calibration only, not model or startup defaults.
    observe(c, @() stimulate(c, modern), 100, 4);
end
verifyTrue(testCase, System.Object.ReferenceEquals(original, c.GetConformance()));
verifyEqual(testCase, setupCount(c), initialSetups, 'Unchanged Core must not repeat setup.');
profile = fullfile(root, 'profile with spaces');
devices = 1;
if modern, devices = 3; end
writeProfile(profile, devices, 5, .2);
reload(c, 'params', profile); waitStarted(c);
if modern
    verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 3);
    verifyRebuilt(testCase, original, c);
end
if modern, pw = 60; else, pw = 100; end
observe(c, @() stimulate(c, modern), pw, 5);
file = fullfile(profile, 'custom parameters.json');
copyfile(fullfile(profile, 'stimParams.json'), file);
beforeFile = c.GetConformance();
reload(c, 'params', file); waitStarted(c);
if modern
    verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 1, 'Explicit file must use startup Core, not sibling Core.');
    verifyRebuilt(testCase, beforeFile, c);
end
if modern, pw = 75; else, pw = 100; end
observe(c, @() stimulate(c, modern), pw, 5);
beforeDefaults = setupCount(c);
reload(c, 'params'); waitStarted(c);
verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 1);
verifyEqual(testCase, setupCount(c), beforeDefaults, 'Unchanged default Core must not repeat setup.');
if modern, amp = 4; else, amp = 5; end
observe(c, @() stimulate(c, modern), pw, amp);
if modern
    reload(c, 'params', profile); waitStarted(c);
    verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 3);
    beforeReturn = c.GetConformance();
    reload(c, 'params'); waitStarted(c);
    verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 1, 'Parameterless reload must return to startup Core.');
    verifyRebuilt(testCase, beforeReturn, c);
    observe(c, @() stimulate(c, modern), 75, 4);
    % CSharp parity: Core-only reset preserves applied calibration/model values.
    writeProfile(root, 2, 7, .4);
    beforeChanged = c.GetConformance();
    reload(c, 'params'); waitStarted(c);
    verifyRebuilt(testCase, beforeChanged, c);
    verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 2);
    observe(c, @() stimulate(c, modern), 70, 7);
    for k = 1:2
        beforeCore = c.GetConformance();
        reload(c, 'core'); waitStarted(c);
        verifyRebuilt(testCase, beforeCore, c);
        observe(c, @() stimulate(c, modern), 70, 7);
    end
    writeText(fullfile(root, 'modelConfig.json'), 'invalid');
    verifyFailure(testCase, @() reload(c, 'params'));
    reload(c, 'core'); waitStarted(c);
    observe(c, @() stimulate(c, modern), 70, 7);
    writeText(fullfile(root, 'stimConfig.json'), 'invalid');
    verifyFailure(testCase, @() reload(c, 'core'));
    verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 2);
    observe(c, @() stimulate(c, modern), 70, 7);
else
    reload(c, 'core'); waitStarted(c);
    verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 1);
    fprintf('Verified legacy calibration-only reload; coordinated all-JSON coverage requires modern payload.\n');
end
end

function testUninitializedErrorsPropagate(testCase)
[root, c] = fixture();
cleanup = onCleanup(@() release(c, root));
verifyError(testCase, @() reload(c, 'params'), 'wss:NotInitialized');
reload(c, 'core');
verifyFalse(testCase, c.Ready());
verifyEqual(testCase, c.TickCount, 0);
end

function reload(c, kind, varargin)
if strcmp(kind, 'core'), c.LoadCoreConfigFile(); else, c.LoadParamsJson(varargin{:}); end
end

function [root, c] = fixture()
root = tempname;
writeProfile(root, 1, 2, 1);
c = wss.StimulationController(wss.WssConfig('ConfigPath', root, ...
    'LogPath', fullfile(root, 'host.log'), 'ConformanceMode', true, 'TickIntervalMs', 1));
end

function verifyFailure(testCase, action)
failed = false;
try
    action();
catch
    failed = true;
end
verifyTrue(testCase, failed, 'Core failure must reach the caller.');
end

function verifyRebuilt(testCase, previous, c)
verifyFalse(testCase, System.Object.ReferenceEquals(previous, c.GetConformance()), ...
    'Changed Core or explicit reset must replace the retired transport.');
verifyGreaterThan(testCase, setupCount(c), 0, 'The replacement must perform actual setup.');
end

function count = setupCount(c)
% NormalSetup sends Clear once per configured device; streaming does not.
% Inspect decoded real emulator requests rather than host state or a test flag.
messages = c.GetConformance().MessageHistory;
count = 0;
for k = 1:messages.Length
    if messages(k).MessageId == uint8(Wss.CoreModule.WSSMessageIDs.Clear)
        count = count + 1;
    end
end
end

function stimulate(c, modern)
if modern, c.StimWithMode('ch2', .5); else, c.StimulateNormalized('ch2', .5); end
end

function observe(c, action, pw, amplitude)
trace = c.GetConformance();
messages = trace.MessageHistory;
baseline = messages(messages.Length).SequenceNumber;
action();
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
error('wss_test:Output', 'Expected channel 2 output was not observed.');
end

function waitStarted(c)
started = tic;
while toc(started) < 5
    if c.Started(), return; end
    pause(.001);
end
error('wss_test:Startup', 'Core did not start.');
end

function writeProfile(directory, devices, amp, gain)
if ~isfolder(directory), mkdir(directory); end
writeText(fullfile(directory, 'stimConfig.json'), sprintf(['{"maxWSS":%d,"firmware":"J03",' ...
    '"useConfigAmpCurves":true,"ampCurves":[{"LowThreshold":0,"LowConst":1,"ExpPower":1,"LinearOffset":-1,"LinearSlope":1}]}'], devices));
channels = cell(1, 9);
for k = 1:9
    channels{k} = sprintf('"%d":{"ampMode":"PW","minPW":50,"maxPW":150,"defaultPA":%d,"IPI":13}', k, amp);
end
writeText(fullfile(directory, 'stimParams.json'), ['{"stim":{"ch":{' strjoin(channels, ',') '}}}']);
writeText(fullfile(directory, 'modelConfig.json'), sprintf('{"calib":{"mode":"P"},"constants":{"PModeProportional":%g}}', gain));
end

function writeText(file, value)
fid = fopen(file, 'w');
if fid < 0, error('wss_test:File', 'Cannot create fixture.'); end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', value);
end

function release(c, root)
c.Shutdown();
if isfolder(root), rmdir(root, 's'); end
end