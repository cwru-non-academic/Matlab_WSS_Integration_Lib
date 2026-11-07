function testSelectedMatlabCompleteness(productRoot, outputRoot)
%TESTSELECTEDMATLABCOMPLETENESS Real assumption skips cannot produce evidence.
% Uses synthetic test fixtures only, never campaign acceptance evidence.
tools = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1, productRoot = fileparts(fileparts(tools)); end
if nargin < 2, outputRoot = tempname; end
assert(~isfolder(outputRoot), 'Fixture output must be new.');
mkdir(outputRoot);
selected = fullfile(outputRoot, 'selected');
mkdir(fullfile(selected, 'tests'));
mkdir(fullfile(selected, 'conformance'));
writeText(fullfile(selected, 'tests', 'TestCanary.m'), [ ...
    "function tests = TestCanary"; "tests = functiontests(localfunctions);"; "end"; ...
    "function testPass(testCase)"; "verifyTrue(testCase, true);"; "end"; ...
    "function testAssumption(testCase)"; ...
    "assumeTrue(testCase, strcmp(getenv('WSS_SELECTION_TEST_MODE'), 'pass'));"; "end"]);
writeText(fullfile(selected, 'conformance', 'runConformance.m'), [ ...
    "function result = runConformance(varargin)"; "result = varargin;"; ...
    "error('wss:testReachedConformance', 'Completeness guard accepted %d arguments.', numel(result));"; "end"]);
writeText(fullfile(selected, 'conformance', 'checkCompatibility.m'), [ ...
    "function result = checkCompatibility(varargin)"; "result = struct('args', {varargin});"; "end"]);
names = {'WSS_SELECTED_ROLE','WSS_SELECTED_PRODUCT','WSS_SELECTED_WRAPPER', ...
    'WSS_SELECTED_TESTS','WSS_SELECTED_OUTPUT','WSS_SELECTION_TEST_MODE', ...
    'WSS_MATLAB_PRODUCT_ROOT','WSS_MATLAB_WRAPPER_ROOT'};
values = cellfun(@getenv, names, 'UniformOutput', false);
oldPath = path;
cleanup = onCleanup(@() restore(names, values, oldPath));
setenv('WSS_SELECTED_ROLE', 'wrapper');
setenv('WSS_SELECTED_PRODUCT', productRoot);
setenv('WSS_SELECTED_WRAPPER', productRoot);
setenv('WSS_SELECTED_TESTS', selected);
setenv('WSS_SELECTED_OUTPUT', outputRoot);
addpath(tools);
for mode = ["skip", "pass"]
    setenv('WSS_SELECTION_TEST_MODE', mode);
    rejected = false;
    try
        runSelectedMatlabTests;
    catch failure
        if mode == "skip"
            rejected = contains(failure.message, 'Selected tests must all pass without skips or incomplete results.');
        else
            rejected = strcmp(failure.identifier, 'wss:testReachedConformance');
        end
        assert(rejected, 'Unexpected fixture failure: %s', failure.message);
    end
    assert(rejected, 'Incomplete tests were accepted or complete tests never reached conformance.');
    assert(~isfile(fullfile(outputRoot, 'selected-summary.json')), 'Fixture produced selected evidence.');
end
fprintf('PASS actual MATLAB pass-plus-assumption-skip rejected; all-pass reaches conformance; no evidence emitted.\n');
end

function writeText(file, lines)
fid = fopen(file, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Cannot write regression fixture.');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', lines);
end

function restore(names, values, oldPath)
for k = 1:numel(names), setenv(names{k}, values{k}); end
path(oldPath);
end