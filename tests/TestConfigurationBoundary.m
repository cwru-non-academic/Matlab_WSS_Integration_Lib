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
writeProfile(root, 1, 4, .5);
reload(c, 'params');
if modern
    observe(c, @() stimulate(c, modern), 75, 4);
else
    % Historical Core reloads calibration only, not model or startup defaults.
    observe(c, @() stimulate(c, modern), 100, 4);
end
verifyTrue(testCase, System.Object.ReferenceEquals(original, c.GetConformance()));
profile = fullfile(root, 'profile with spaces');
writeProfile(profile, 1, 5, .2);
reload(c, 'params', profile);
if modern, pw = 60; else, pw = 100; end
observe(c, @() stimulate(c, modern), pw, 5);
file = fullfile(profile, 'custom parameters.json');
copyfile(fullfile(profile, 'stimParams.json'), file);
reload(c, 'params', file);
if modern, pw = 75; else, pw = 100; end
observe(c, @() stimulate(c, modern), pw, 5);
reload(c, 'params');
if modern, amp = 4; else, amp = 5; end
observe(c, @() stimulate(c, modern), pw, amp);
if modern
    % Active all-JSON Core reload, not snapshot-host retained-value semantics.
    writeProfile(root, 2, 7, .4);
    reload(c, 'params'); waitStarted(c);
    verifyEqual(testCase, double(c.GetCoreConfigCTRL().MaxWss), 2);
    observe(c, @() stimulate(c, modern), 70, 7);
    for k = 1:2
        reload(c, 'core'); waitStarted(c);
        observe(c, @() stimulate(c, modern), 70, 7);
    end
    writeText(fullfile(root, 'modelConfig.json'), 'invalid');
    verifyFailure(testCase, @() reload(c, 'params'));
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
verifyError(testCase, @() reload(c, 'core'), 'wss:NotInitialized');
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