function results = runConformance(factory, csLibDir, stage)
%RUNCONFORMANCE Exercise the production wrapper with Core's canonical catalog.
% Optional factory enables the consuming CLI to run the same scenarios through
% its production createController. No hardware or simulated TestMode is used.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1, factory = @wss.StimulationController; end
if nargin < 2, csLibDir = fullfile(root, 'Cs_Libraries'); end
if nargin < 3, stage = 'single'; end
assert(ismember(stage, {'single','multi'}), 'Select single or multi conformance stage.');
% Initialize assembly loading through production code before reading catalog.
wss.loadRuntime(wss.WssConfig('CsLibDir', csLibDir, 'ConformanceMode', true));
catalog = Wss.Testing.WssBehaviorScenarios.NormalizedStimulation;
ids = {'initialization', 'direct-analog'};
for k = 0:catalog.Count - 1, ids{end + 1} = char(catalog.Item(k).Id); end %#ok<AGROW>
ids = [ids, {'runtime-event-edit', 'stop-stimulation'}];
if strcmp(stage, 'single')
    sequences = Wss.Testing.WssStimulationSequences.SingleDevice;
    layered = Wss.Testing.WssStimulationSequences.LayeredSingleDevice;
    required = {'analog.multichannel-isolation','normalized.multichannel-isolation', ...
        'modeled.p.pw.single','modeled.p.pa.single','modeled.pd.pw.single','modeled.pd.pa.single'};
else
    sequences = Wss.Testing.WssStimulationSequences.MultipleDevices;
    layered = Wss.Testing.WssStimulationSequences.LayeredMultipleDevices;
    required = {'analog.multidevice-isolation','normalized.multidevice-isolation', ...
        'modeled.p.pw.multi','modeled.p.pa.multi','modeled.pd.pw.multi','modeled.pd.pa.multi'};
end
baseSequences = sequences;
sequences = cell(1, listCount(baseSequences) + listCount(layered));
for k = 1:listCount(baseSequences), sequences{k} = listItem(baseSequences, k - 1); end
for k = 1:listCount(layered), sequences{listCount(baseSequences) + k} = listItem(layered, k - 1); end
sequenceIds = cell(1, listCount(sequences));
for k = 1:numel(sequenceIds), sequenceIds{k} = char(listItem(sequences, k - 1).Id); end
assert(isequal(sort(sequenceIds), sort(required)), 'Shared sequence inventory is missing, duplicated or unexpected.');
legacyCount = numel(ids);
ids = [ids, sequenceIds];
results = repmat(struct('Id', '', 'Passed', false, 'Failure', ''), 1, numel(ids));
for k = 1:numel(ids)
    results(k).Id = ids{k};
    try
        if k <= legacyCount
            scenario(factory, csLibDir, k, catalog);
        else
            sequence(factory, csLibDir, listItem(sequences, k - legacyCount - 1));
        end
        results(k).Passed = true;
    catch failure
        results(k).Failure = getReport(failure, 'extended', 'hyperlinks', 'off');
    end
    fprintf('%s: %s\n', ids{k}, string(results(k).Passed));
end
if ~all([results.Passed])
    failures = {results(~[results.Passed]).Failure};
    error('wss:ConformanceFailed', '%s', strjoin(failures, newline));
end
end

function sequence(factory, payload, item)
directory = tempname;
mkdir(directory);
try
    item.WriteFixture(directory);
    config = wss.WssConfig('ConfigPath', directory, 'LogPath', fullfile(directory, 'host.log'), ...
        'CsLibDir', payload, 'ConformanceMode', true, 'MaxSetupTries', 1, 'TickIntervalMs', 1);
    controller = factory(config);
catch failure
    rmdir(directory, 's'); rethrow(failure);
end
cleanup = onCleanup(@() cleanupFixture(controller, directory));
controller.Initialize();
conformance = controller.GetConformance();
assert(~isempty(conformance), 'No Core conformance source.');
allTargets = false;
for attempt = 1:3000
    allTargets = controller.Started();
    for unit = 1:double(item.DeviceCount)
        observed = findMessage(conformance.StimulationHistory, @(m) double(m.Target) == 128 + unit);
        allTargets = allTargets && ~isempty(observed);
    end
    if allTargets, break; end
    pause(0.001);
end
assert(allTargets, 'Not all configured targets streamed.');
steps = item.Steps;
for k = 0:listCount(steps) - 1
    step = listItem(steps, k);
    expected = step.Expectation;
    baseline = conformance.CaptureStimulationBaseline();
    step.PrepareReload(directory);
    if step.ReloadParameters, controller.LoadParamsJson(); end
    if step.ReloadModel
        modelController = controller.GetModelConfigCTRL();
        modelController.LoadModelJson();
    end
    if step.Modeled
        controller.StimWithMode(channel(step.GlobalChannel), double(step.Input));
    elseif step.Normalized
        controller.StimulateNormalized(channel(step.GlobalChannel), double(step.Input));
    else
        controller.StimulateAnalog(channel(step.GlobalChannel), double(expected.PulseWidth), ...
            double(expected.PulseAmplitude), double(expected.InterPulseInterval));
    end
    for attempt = 1:2000
        result = Wss.Testing.WssStimulationWindow.Evaluate(conformance, baseline, expected, int32(item.DeviceCount));
        if result.Settled || listCount(result.Failures) > 0, break; end
        pause(0.001);
    end
    assert(result.Passed, '%s/%s: %s', char(item.Id), char(step.Id), char(result.Diagnostics));
end
end

function scenario(factory, payload, index, normalized)
directory = tempname;
mkdir(directory);
try
    writeFixture(directory);
    config = wss.WssConfig('ConfigPath', directory, 'LogPath', fullfile(directory, 'host.log'), ...
        'CsLibDir', payload, 'ConformanceMode', true, 'MaxSetupTries', 1, 'TickIntervalMs', 1);
    controller = factory(config);
catch failure
    rmdir(directory, 's'); rethrow(failure);
end
cleanup = onCleanup(@() cleanupFixture(controller, directory));
controller.Initialize();
conformance = controller.GetConformance();
assert(~isempty(conformance), 'Production wrapper did not expose Core conformance.');
startup = Wss.Testing.WssBehaviorScenarios.Initialization;
operational = false; streamed = false;
for attempt = 1:3000
    operational = operational || controller.Started();
    streamed = streamed || listCount(conformance.StimulationHistory) > 0;
    if (~startup.RequiresOperationalState || operational) && (~startup.RequiresStreamObservation || streamed), break; end
    pause(0.001);
end
if startup.RequiresOperationalState, assert(operational, 'Initialization did not become operational.'); end
if startup.RequiresStreamObservation, assert(streamed, 'No startup stream was observed.'); end
if index == 1
    result = conformance.ValidateInitialization();
    if startup.RequiresSuccessfulConformance, assert(result.Passed, diagnostics(result)); end
elseif index == 2
    item = Wss.Testing.WssBehaviorScenarios.DirectAnalog;
    baseline = conformance.CaptureStimulationBaseline();
    amp = double(item.AmplitudeMa);
    assert(amp == fix(amp), 'Analog wrapper amplitude must be a whole number.');
    controller.StimulateAnalog(channel(item.Channel), double(item.PulseWidth), amp, double(item.InterPulseInterval));
    result = waitStimulation(conformance, baseline, item.Expectation);
    assert(result.Passed, diagnostics(result));
elseif index <= 2 + normalized.Count
    item = normalized.Item(index - 3);
    baseline = conformance.CaptureStimulationBaseline();
    controller.StimulateNormalized(channel(item.Channel), double(item.Input));
    result = waitStimulation(conformance, baseline, item.Expectation);
    assert(result.Passed, diagnostics(result));
elseif index == 3 + normalized.Count
    item = Wss.Testing.WssBehaviorScenarios.RuntimeEventEdit;
    initial = lastStream(conformance.MessageHistory);
    paused = controller.UpdateEventRatio(target(item.Target), double(item.Ratio), double(item.EventId));
    edit = []; sync = []; resumed = [];
    for attempt = 1:2000
        history = conformance.MessageHistory;
        edit = findMessage(history, @(m) m.SequenceNumber > initial.SequenceNumber && ...
            m.Target == item.Target && m.MessageId == item.ExpectedMessageId && ...
            m.Payload.Length >= 5 && m.Payload(3) == item.EventId && ...
            m.Payload(4) == item.ExpectedSubcommand && m.Payload(5) == item.ExpectedValue);
        sync = findMessage(history, @(m) m.SequenceNumber > initial.SequenceNumber && ...
            m.MessageId == uint8(Wss.CoreModule.WSSMessageIDs.SyncGroup));
        if ~isempty(edit), resumed = findMessage(history, @(m) m.SequenceNumber > edit.SequenceNumber && isStream(m)); end
        resumeMatches = (~isempty(resumed) == logical(item.ResumeStreamingExpected)) && ...
            (controller.Started() == logical(item.ResumeStreamingExpected));
        if ~isempty(edit) && resumeMatches && (~isempty(sync) == logical(item.AdditionalSyncGroupExpected)), break; end
        pause(0.001);
    end
    result = conformance.ValidateInitialization();
    assert(paused, 'Core did not pause for the Event edit.');
    assert(~isempty(edit), 'Core did not transmit the canonical Event edit.');
    assert(~isempty(sync) == logical(item.AdditionalSyncGroupExpected), 'Event edit SyncGroup mismatch.');
    assert(~isempty(resumed) == logical(item.ResumeStreamingExpected), 'Event edit stream resumption mismatch.');
    assert(controller.Started() == logical(item.ResumeStreamingExpected), 'Wrapper streaming state mismatch.');
    if item.RequiresSuccessfulConformance, assert(result.Passed, diagnostics(result)); end
else
    item = Wss.Testing.WssBehaviorScenarios.StopStimulation;
    initial = lastStream(conformance.MessageHistory);
    controller.StopStimulation(target(item.Target));
    stop = []; completed = [];
    for attempt = 1:2000
        history = conformance.MessageHistory;
        stop = findMessage(history, @(m) m.SequenceNumber > initial.SequenceNumber && ...
            m.Target == item.Target && m.MessageId == item.ExpectedMessageId && ...
            m.Payload.Length >= 3 && m.Payload(3) == item.ExpectedOperationValue);
        if ~isempty(stop) && ~controller.Started() && controller.Ready()
            history = conformance.MessageHistory;
            final = listItem(history, listCount(history) - 1);
            completed = final.SequenceNumber;
            break;
        end
        pause(0.001);
    end
    startedAfter = false;
    for attempt = 1:20, pause(0.001); startedAfter = startedAfter || controller.Started(); end
    resumed = [];
    if ~isempty(completed)
        resumed = findMessage(conformance.MessageHistory, @(m) m.SequenceNumber > completed && isStream(m));
    end
    assert(~isempty(stop), 'Stop command was not observed.');
    assert(~isempty(completed), 'Stop did not reach Ready and not Started.');
    assert(~isempty(resumed) == logical(item.ResumeStreamingExpected), 'Post-stop streams were unexpected.');
    assert(startedAfter == logical(item.ResumeStreamingExpected), 'State changed after stop completion.');
    assert(controller.Started() == logical(item.ResumeStreamingExpected), 'Final wrapper stop state mismatch.');
end
end

function result = waitStimulation(conformance, baseline, expectation)
result = conformance.ValidateStimulation(expectation, baseline);
for attempt = 1:2000
    if result.Passed, break; end
    pause(0.001);
    result = conformance.ValidateStimulation(expectation, baseline);
end
end

function found = findMessage(history, predicate)
found = [];
for k = 0:listCount(history) - 1
    item = listItem(history, k);
    if predicate(item), found = item; return; end
end
end

function found = lastStream(history)
found = [];
for k = 0:listCount(history) - 1
    item = listItem(history, k);
    if isStream(item), found = item; end
end
if isempty(found), error('wss:MissingStream', 'No baseline stream was observed.'); end
end

function value = isStream(item)
id = double(item.MessageId);
value = id >= double(Wss.CoreModule.WSSMessageIDs.StreamChangeAll) && ...
    id <= double(Wss.CoreModule.WSSMessageIDs.StreamChangeNoPA);
end

function value = channel(index)
names = {'thumb', 'index', 'middle', 'ring', 'pinky'};
if double(index) <= numel(names), value = names{double(index)};
else, value = sprintf('ch%d', index); end
end

function value = target(wireValue)
values = [double(Wss.CoreModule.WssTarget.Broadcast), double(Wss.CoreModule.WssTarget.Wss1), ...
    double(Wss.CoreModule.WssTarget.Wss2), double(Wss.CoreModule.WssTarget.Wss3)];
value = find(values == double(wireValue), 1) - 1;
if isempty(value), error('wss:UnsupportedTarget', 'Unsupported canonical target.'); end
end

function value = diagnostics(result)
items = result.Failures;
lines = cell(1, listCount(items));
for k = 0:listCount(items) - 1, lines{k + 1} = char(listItem(items, k)); end
value = strjoin(lines, newline);
if isempty(value), value = 'Core conformance failed without diagnostics.'; end
end

function count = listCount(items)
if iscell(items), count = numel(items);
elseif isa(items, 'System.Array'), count = double(items.Length); else, count = double(items.Count); end
end

function item = listItem(items, zeroBasedIndex)
if iscell(items), item = items{zeroBasedIndex + 1};
elseif isa(items, 'System.Array'), item = items(zeroBasedIndex + 1); else, item = items.Item(zeroBasedIndex); end
end

function writeFixture(directory)
fixture = Wss.Testing.WssBehaviorScenarios.StimulationFixture;
core = struct('maxWSS', 1, 'firmware', 'J03', 'broadcastTarget', '0x8F', ...
    'wssTargets', {{'0x81','0x82','0x83'}}, 'useConfigAmpCurves', true, ...
    'ampCurves', struct('LowThreshold', double(fixture.CurveLowThreshold), ...
    'LowConst', double(fixture.CurveLowConstant), 'ExpPower', double(fixture.CurveExponent), ...
    'LinearOffset', double(fixture.CurveLinearOffset), 'LinearSlope', double(fixture.CurveLinearSlope)));
core.ampCurves = {core.ampCurves}; % Preserve the canonical one-element JSON array.
params = struct('ampMode', char(fixture.AmplitudeMode), 'minPW', double(fixture.MinimumPulseWidth), ...
    'maxPW', double(fixture.MaximumPulseWidth), 'minPA', 0, 'maxPA', 0, ...
    'defaultPA', double(fixture.DefaultAmplitudeMa), 'defaultPW', 50, 'IPI', double(fixture.InterPulseInterval));
writeJson(fullfile(directory, 'stimConfig.json'), jsonencode(core));
% JSON channel keys are numeric text, which MATLAB struct fields cannot express.
key = sprintf('%d', Wss.Testing.WssBehaviorScenarios.DirectAnalog.Channel);
writeJson(fullfile(directory, 'stimParams.json'), ['{"stim":{"ch":{"' key '":' jsonencode(params) '}}}']);
end

function writeJson(filename, text)
file = fopen(filename, 'w', 'n', 'UTF-8');
if file < 0, error('wss:FixtureWrite', 'Cannot write %s.', filename); end
cleanup = onCleanup(@() fclose(file));
fprintf(file, '%s', text);
end

function cleanupFixture(controller, directory)
controller.Shutdown();
if isfolder(directory), rmdir(directory, 's'); end
end
