function contract = assertNativeTestContract(root, role, ids)
%ASSERTNATIVETESTCONTRACT Require exact native discovery/results for this source.
contract = jsondecode(fileread(fullfile(root, 'ci', 'native-test-contract.json')));
assert(strcmp(contract.schema, 'wss-matlab-native-tests/v1') && strcmp(contract.role, role), ...
    'Native test contract role/schema mismatch.');
expected = string(contract.ids);
actual = string(ids);
assert(~isempty(expected) && numel(unique(expected)) == numel(expected) && ...
    numel(actual) == numel(expected) && numel(unique(actual)) == numel(actual) && ...
    isequal(sort(expected(:)), sort(actual(:))), 'Native test discovery/results differ from source contract.');
end
