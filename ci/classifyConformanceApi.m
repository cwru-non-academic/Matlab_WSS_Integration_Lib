function name = classifyConformanceApi(baseline, types, modern)
%CLASSIFYCONFORMANCEAPI Complete baseline and all-or-none modern capabilities.
assert(islogical(baseline) && numel(baseline) == 6 && all(baseline), 'Incomplete legacy canonical API.');
assert(islogical(types) && numel(types) == 6 && islogical(modern) && numel(modern) == 14, 'Invalid API inventory.');
if all(types) && all(modern)
    name = 'layered-v1';
elseif ~any(types) && ~any(modern)
    name = 'legacy-v1';
else
    error('wss:PartialConformanceApi', 'Partial or intermediate layered API cannot fall back to legacy.');
end
end
