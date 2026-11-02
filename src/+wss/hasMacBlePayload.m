function supported = hasMacBlePayload(csLibDir)
%HASMACBLEPAYLOAD Classify packaged Mac capability without loading assemblies.
% Only the recorded historical 25-file bootstrap may report unsupported.
% Declared/partial/missing unknown Mac assets fail; this is not an ABI probe.
directory = fullfile(csLibDir, 'backends', 'macos');
managed = isfile(fullfile(directory, 'WSS.Transport.BLE.MacOS.dll'));
native = isfile(fullfile(directory, 'libwss_macos_ble.dylib'));
if managed && native, supported = true; return; end
knownLegacy = false;
recordPath = fullfile(csLibDir, 'payload-source.json');
if isfile(recordPath)
    record = jsondecode(fileread(recordPath));
    if isfield(record, 'schema') && isfield(record, 'files') && numel(record.files) == 25
        reference = '79322a82d285cc526c77ea660beb2993cb04f5d9';
        repository = 'cwru-non-academic/Python_WSS_Integration_Lib';
        if strcmp(record.schema, 'wss-matlab-payload-source/v1')
            knownLegacy = isfield(record, 'source_commit') && isfield(record, 'source_repository') && ...
                strcmp(record.source_commit, reference) && strcmp(record.source_repository, repository);
        elseif strcmp(record.schema, 'wss-matlab-projection/v1')
            knownLegacy = isfield(record, 'bootstrap_reference') && isequal(record.bootstrap_reference, true) && ...
                isfield(record, 'reference_source') && isfield(record.reference_source, 'commit') && ...
                isfield(record.reference_source, 'repository') && ...
                strcmp(record.reference_source.commit, reference) && strcmp(record.reference_source.repository, repository);
        end
        if knownLegacy && isfield(record.files, 'path')
            paths = {record.files.path};
        elseif knownLegacy && isfield(record.files, 'source')
            paths = {record.files.source};
        else
            paths = {};
            knownLegacy = false;
        end
        knownLegacy = knownLegacy && ~any(startsWith(paths, 'backends/macos/'));
    end
end
if ~managed && ~native && knownLegacy
    supported = false;
    return;
end
error('wss:IncompleteMacPayload', ...
    'Mac BLE requires both packaged managed and native files; this is not the recorded legacy payload.');
end
