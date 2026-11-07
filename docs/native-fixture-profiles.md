# Native fixture profiles

The modern fixture remains the exact Git source from ad96c800e4ec9045c8961441c235575b53004924. Its SHA-256 is over UTF-8 LF bytes, not Windows checkout CRLF bytes. The earlier 64eea759 pin hashed the CRLF checkout; the normalized pin is 2f85d4bb. Both source bytes are covered by an EOL regression; changed content is rejected.

The legacy fixture is the unchanged historical runConformance.m from 9aa89b07364c1c79758a1403abc56d69981e9d56, preserved in conformance/legacy. The trusted product dispatcher verifies the selected fixture hash. No selected test configuration can choose a mandatory profile.

After verifying the full universal projection, native reflection binds the profile to producer identity, projection digest and actual loaded Core DLL hash. Legacy requires all six historical catalog getters and absence of all six modern types. Modern requires every type and member sentinel, executes the original ten cases plus six single-device sequences, then all ten cases plus six multi-device sequences. Partial and intermediate APIs fail closed. Existing producer policies can still validate legacy; independently selected campaigns require the modern profile before executing selected code.

Mandatory evidence includes both inventories and the verified profile binding. CI completion, promotion verification and provenance normalization validate the same contract. Source and payload hashes remain independent. Native child processes do not inherit credential environment variables or GitHub output/environment/state/path handles; parent environment restoration is tested even on failure.

This changes neither committed product payloads nor release authority. Candidate staging continues through the existing resolver/projection contract. Tests never open physical transports.
