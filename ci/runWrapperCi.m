function summary = runWrapperCi(purpose)
%RUNWRAPPERCI Execute real MATLAB behavior or distinct load-only compatibility.
root = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
cleanup = onCleanup(@() path(oldPath));
dotnetenv('core', Version='8');
addpath(fullfile(root, 'src'), fullfile(root, 'conformance'));
switch char(purpose)
    case 'behavioral'
        files = [dir(fullfile(root, 'src', '**', '*.m')); dir(fullfile(root, 'tests', '**', '*.m')); ...
            dir(fullfile(root, 'conformance', '*.m')); dir(fullfile(root, 'ci', '*.m'))];
        for k = 1:numel(files)
            file = fullfile(files(k).folder, files(k).name);
            findings = checkcode(file, '-id');
            if ~isempty(findings), error('wss_ci:Analyzer', 'Code Analyzer findings in %s: %s', file, jsonencode(findings)); end
        end
        tests = runtests(fullfile(root, 'tests'));
        assertSuccess(tests);
        scenarios = runConformance();
        summary = struct('purpose', purpose, 'matlab', version, 'testsPassed', sum([tests.Passed]), ...
            'scenariosPassed', sum([scenarios.Passed]), 'cases', {scenarios});
    case 'compatibility'
        summary = checkCompatibility();
        summary.purpose = purpose;
        summary.matlab = version;
    otherwise
        error('wss_ci:Purpose', 'Select behavioral or compatibility.');
end
directory = fullfile(root, 'artifacts', 'ci');
if ~isfolder(directory), mkdir(directory); end
file = fopen(fullfile(directory, [char(purpose) '.json']), 'w', 'n', 'UTF-8');
if file < 0, error('wss_ci:Evidence', 'Cannot write CI evidence.'); end
closeFile = onCleanup(@() fclose(file));
fprintf(file, '%s', jsonencode(summary));
disp(summary);
end
