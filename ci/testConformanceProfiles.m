function testConformanceProfiles()
%TESTCONFORMANCEPROFILES Every missing or unexpected sentinel is rejected.
baseline = true(1, 6); types = true(1, 6); modern = true(1, 14);
assert(strcmp(classifyConformanceApi(baseline, types, modern), 'layered-v1'));
assert(strcmp(classifyConformanceApi(baseline, ~types, ~modern), 'legacy-v1'));
for k = 1:numel(baseline)
    value = baseline; value(k) = false;
    reject(@() classifyConformanceApi(value, types, modern));
    reject(@() classifyConformanceApi(value, ~types, ~modern));
end
for k = 1:numel(types)
    value = types; value(k) = false;
    reject(@() classifyConformanceApi(baseline, value, modern));
    reject(@() classifyConformanceApi(baseline, ~value, ~modern));
end
for k = 1:numel(modern)
    value = modern; value(k) = false;
    reject(@() classifyConformanceApi(baseline, types, value));
    reject(@() classifyConformanceApi(baseline, ~types, ~value));
end
end

function reject(action)
failed = false;
try
    action();
catch
    failed = true;
end
assert(failed, 'Partial API unexpectedly accepted.');
end
