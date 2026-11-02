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
verifyEmpty(testCase, controller.LastCoreError);
controller.resetRadio();
verifyFalse(testCase, controller.Ready());
verifyEqual(testCase, controller.TickCount, 0);
verifyError(testCase, @() controller.StimWithMode('thumb', 0.5), 'wss:NotInitialized');
end

function testTransportSelectionAndLegacyAliases(testCase)
verifyEqual(testCase, wss.WssConfig().Transport, 'serial');
verifyEqual(testCase, wss.WssConfig('TestMode', true).Transport, 'test');
verifyTrue(testCase, wss.WssConfig('Transport', 'conformance').ConformanceMode);
verifyError(testCase, @() wss.WssConfig('Transport', 'wifi'), 'wss:UnsupportedTransport');
verifyError(testCase, @() wss.WssConfig('Transport', 'ble', 'TestMode', true), 'wss:ConflictingTransport');
end

function testBleRequiresExplicitSelection(testCase)
verifyError(testCase, @() wss.WssConfig('Transport', 'ble'), 'wss:BleSelectorRequired');
verifyError(testCase, @() wss.WssConfig('Transport', 'ble', 'BleDeviceName', '  '), 'wss:BleSelectorRequired');
config = wss.WssConfig('Transport', 'BLE', 'BleAutoSelect', true);
verifyEqual(testCase, config.Transport, 'ble');
verifyTrue(testCase, config.BleAutoSelect);
end

function testDeclaredMacCapabilityCannotHideMissingAssets(testCase)
% Synthetic classification fixtures only: no executable native proof.
directory = tempname;
mkdir(directory);
cleanup = onCleanup(@() rmdir(directory, 's'));
files = repmat(struct('path', ''), 1, 25);
for k = 1:25, files(k).path = sprintf('legacy-fixture/asset-%d', k); end
legacy = struct('schema', 'wss-matlab-payload-source/v1', ...
    'source_repository', 'cwru-non-academic/Python_WSS_Integration_Lib', ...
    'source_commit', '79322a82d285cc526c77ea660beb2993cb04f5d9', 'files', files);
writeFixtureFile(fullfile(directory, 'payload-source.json'), jsonencode(legacy));
verifyFalse(testCase, wss.hasMacBlePayload(directory));
record = struct('schema', 'wss-matlab-projection/v1', 'bootstrap_reference', false, ...
    'files', struct('source', {'backends/macos/WSS.Transport.BLE.MacOS.dll', ...
    'backends/macos/libwss_macos_ble.dylib'}));
writeFixtureFile(fullfile(directory, 'payload-source.json'), jsonencode(record));
verifyError(testCase, @() wss.hasMacBlePayload(directory), 'wss:IncompleteMacPayload');
mkdir(fullfile(directory, 'backends', 'macos'));
writeFixtureFile(fullfile(directory, 'backends', 'macos', 'WSS.Transport.BLE.MacOS.dll'), 'not an assembly');
verifyError(testCase, @() wss.hasMacBlePayload(directory), 'wss:IncompleteMacPayload');
writeFixtureFile(fullfile(directory, 'backends', 'macos', 'libwss_macos_ble.dylib'), 'not a native library');
verifyTrue(testCase, wss.hasMacBlePayload(directory));
end

function writeFixtureFile(file, text)
handle = fopen(file, 'w');
assert(handle >= 0, 'Cannot create fixture.');
cleanup = onCleanup(@() fclose(handle));
fprintf(handle, '%s', text);
end
