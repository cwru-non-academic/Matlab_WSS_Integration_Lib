function runSelectedMatlabTests()
% Trusted bootstrap. The selected checkout contributes tests, never CI code.
assert(strcmp(version('-release'), '2026b'), 'MATLAB R2026b required.');
role = getenv('WSS_SELECTED_ROLE');
product = getenv('WSS_SELECTED_PRODUCT');
wrapper = getenv('WSS_SELECTED_WRAPPER');
testRoot = getenv('WSS_SELECTED_TESTS');
output = getenv('WSS_SELECTED_OUTPUT');
oldPath = path;
cleanup = onCleanup(@() path(oldPath));
restoredefaultpath;
dotnetenv('core', Version='8');
setenv('WSS_MATLAB_PRODUCT_ROOT', product);
setenv('WSS_MATLAB_WRAPPER_ROOT', wrapper);
addpath(fullfile(wrapper, 'src'), fullfile(product, 'src'));
if strcmp(role, 'cli'), addpath(fullfile(wrapper, 'conformance')); end
addpath(fullfile(testRoot, 'conformance'));
assert(startsWith(which('wss.WssConfig'), [wrapper filesep]), 'Wrapper source escaped fixed product.');
if strcmp(role, 'cli')
    assert(startsWith(which('wss_cli.main'), [product filesep]), 'CLI source escaped fixed product.');
end
files = [dir(fullfile(testRoot, 'tests', '**', '*.m')); dir(fullfile(testRoot, 'conformance', '**', '*.m'))];
for k = 1:numel(files)
    file = fullfile(files(k).folder, files(k).name);
    findings = checkcode(file, '-id');
    assert(isempty(findings), 'Selected Code Analyzer findings: %s', jsonencode(findings));
end
tests = runtests(fullfile(testRoot, 'tests'));
assert(~isempty(tests), 'Selected test suite is empty.');
assertSuccess(tests);
if strcmp(role, 'wrapper')
    assert(startsWith(which('runConformance'), [testRoot filesep]), 'Wrong selected conformance source.');
    scenarios = runConformance(@wss.StimulationController, fullfile(wrapper, 'Cs_Libraries'), 'single');
    multi = runConformance(@wss.StimulationController, fullfile(wrapper, 'Cs_Libraries'), 'multi');
    compatibility = checkCompatibility(fullfile(wrapper, 'Cs_Libraries'));
else
    assert(startsWith(which('runCliConformance'), [testRoot filesep]), 'Wrong selected CLI conformance source.');
    scenarios = runCliConformance(wrapper, fullfile(wrapper, 'Cs_Libraries'), product);
    multi = scenarios([]);
    compatibility = checkCliCompatibility(wrapper, product);
end
assert(startsWith(which('wss.WssConfig'), [wrapper filesep]), 'Wrapper source changed during selected tests.');
if strcmp(role, 'cli')
    assert(startsWith(which('wss_cli.main'), [product filesep]), 'CLI source changed during selected tests.');
end
assert(all([scenarios.Passed]) && all([multi.Passed]), 'Selected conformance failed.');
summary = struct('testsPassed', sum([tests.Passed]), 'scenarios', scenarios, ...
    'multi', multi, 'compatibility', compatibility, 'matlab', version);
file = fopen(fullfile(output, 'selected-summary.json'), 'w', 'n', 'UTF-8');
assert(file >= 0, 'Cannot write selected summary.');
closeFile = onCleanup(@() fclose(file));
fprintf(file, '%s', jsonencode(summary));
end
