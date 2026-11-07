function [cases, multi, profile] = runMandatoryConformance(factory, payload)
%RUNMANDATORYCONFORMANCE Trusted product fixture dispatch, never selected tests.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1, factory = @wss.StimulationController; end
if nargin < 2, payload = fullfile(root, 'Cs_Libraries'); end
config = jsondecode(fileread(fullfile(root, '.github', 'matlab-ci.json')));
profile = getConformanceProfile(payload);
oldPath = path;
cleanup = onCleanup(@() path(oldPath));
clear runConformance;
if strcmp(profile.name, 'legacy-v1')
    fixture = fullfile(root, config.legacy_fixture_path);
    expected = config.legacy_fixture_sha256;
    profile.fixture_commit = config.legacy_fixture_commit;
    profile.fixture_path = config.legacy_fixture_path;
else
    fixture = fullfile(root, config.fixture_path);
    expected = config.fixture_sha256;
    profile.fixture_commit = config.fixture_commit;
    profile.fixture_path = config.fixture_path;
end
profile.fixture_sha256 = expected;
text = strrep(fileread(fixture), sprintf('\r\n'), newline);
assert(strcmp(hashBytes(unicode2native(text, 'UTF-8')), expected), 'Canonical fixture hash mismatch.');
addpath(fileparts(fixture), '-begin');
assert(strcmp(which('runConformance'), fixture), 'Canonical fixture path mismatch.');
cases = runConformance(factory, payload);
multi = cases([]);
if strcmp(profile.name, 'layered-v1')
    multi = runConformance(factory, payload, 'multi');
    checkCases(cases, config.expected_cases);
    checkCases(multi, [config.legacy_expected_cases; config.multidevice_expected_cases]);
else
    checkCases(cases, config.legacy_expected_cases);
end
clear runConformance;
end

function checkCases(cases, expected)
assert(numel(cases) == numel(expected) && isequal(sort({cases.Id}), sort(reshape(expected, 1, []))), ...
    'Canonical case inventory mismatch.');
assert(all([cases.Passed]) && all(cellfun(@isempty, {cases.Failure})), 'Canonical fixture failed.');
end

function value = hashBytes(bytes)
algorithm = System.Security.Cryptography.SHA256.Create();
cleanup = onCleanup(@() algorithm.Dispose());
value = lower(reshape(dec2hex(uint8(algorithm.ComputeHash(uint8(bytes))), 2).', 1, []));
end
