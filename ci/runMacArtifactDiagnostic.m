function summary = runMacArtifactDiagnostic(role, sourceRoot, wrapperRoot, evidenceDir)
%RUNMACARTIFACTDIAGNOSTIC Test a verified disposable payload without radio access.
assert(ismac && strcmp(computer, 'MACA64'), 'This diagnostic requires native macOS arm64 MATLAB.');
oldPath = path;
cleanup = onCleanup(@() path(oldPath));
dotnetenv('core', Version='8');
addpath(fullfile(wrapperRoot, 'src'), fullfile(wrapperRoot, 'conformance'));
switch char(role)
    case 'wrapper'
        summary = checkCompatibility(fullfile(wrapperRoot, 'Cs_Libraries'));
    case 'cli'
        addpath(fullfile(sourceRoot, 'src'), fullfile(sourceRoot, 'conformance'));
        summary = checkCliCompatibility(wrapperRoot);
        assert(strcmp(summary.CliBleSelection, 'passed'), 'Real Mac CLI BLE selection must pass.');
    otherwise
        error('wss_ci:Role', 'Unknown diagnostic role.');
end
assert(strcmp(summary.Ble, 'passed'), 'Real Mac BLE loading must pass; legacy unsupported is not success.');
assert(strcmp(summary.Backend, 'WSS.Transport.BLE.MacOS'), 'Expected the actual Mac backend.');
summary.role = role;
summary.matlab = version;
summary.purpose = 'preparation-only-load-and-abi';
summary.hardwareConnected = false;
file = fopen(fullfile(evidenceDir, 'mac-load-abi.json'), 'w', 'n', 'UTF-8');
if file < 0, error('wss_ci:Evidence', 'Cannot write Mac diagnostic evidence.'); end
closeFile = onCleanup(@() fclose(file));
fprintf(file, '%s', jsonencode(summary));
disp(summary);
end
