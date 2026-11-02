# MATLAB propagation preparation

Status: receiver source prepared; **disabled**. `.github/matlab-ci.json` has `baseline_ready: false`, the existing pipeline contract has `enabled: false`, and promotion jobs additionally require repository variable `WSS_MATLAB_PROPAGATION_ENABLED` equal to `true`. This change does not set that variable, change rulesets/App access, or dispatch Core candidates.

## Trust and review sequence

1. Promote working native CI from dev to main through the two review PRs; preserve dev work. Configure main/dev rulesets using the four existing check names per repository after verifying green results.
2. Verify existing App installation and availability of `WSS_GITHUB_APP_ID` / `WSS_GITHUB_APP_PRIVATE_KEY` without creating or expanding credentials. Current metadata reads did not establish availability; organization-level reads were denied, which does not prove absence.
3. Review and merge the disabled receiver setup, then validate the first exact **canonical Core dev push** artifact only after activation is explicitly approved. Ordinary PR artifacts and this setup PR's green CI are not producer proof.
4. Core's dispatcher must separately add the MATLAB wrapper receiver after its producer completes all required jobs. It passes the exact repository, commit, run ID, artifact ID, archive, and SHA256 tuple. No Core edit is included here.
5. The wrapper resolves that exact successful producer and verifies archive checksum, exact ZIP paths, complete universal inventory, per-file hashes, both current source SHAs, native suite digest, native MATLAB behavior and all platform preflights. Only after successful source-bound evidence does it mint a target-only write token and create a **dependency-only dev PR**. No auto-merge.
6. After a human merges that exact bot PR, the wrapper checks the actual merged payload, exact approval marker, restricted diff, dev ancestry, and all four normal final-head PR contexts before dispatching the CLI receiver.
7. The CLI revalidates original proof and the reviewed merge, then runs a fresh native preflight against the actual merged wrapper and current CLI source. It creates a **gitlink-only dev PR**, again with human merge. It never silently changes application code or substitutes a successful older run.

Correlated runs/branches are reused only when their exact identity and intended tree match. Ambiguous, stale, orphan, expired, failed, or uncertain outcomes stop publication for inspection. No force pushes, rollback PRs, release publication, latest-artifact fallback, or automatic merges.

New candidates require the exact 27-file universal inventory, including both macOS BLE files. Only the explicitly identified historical reference-copy bootstrap retains its recorded 25-file inventory; it is never accepted as a new candidate. The existing `Cs_Libraries/payload-source.json` remains immutable reference-copy metadata; the bootstrap manifest explicitly records no canonical Core candidate. An identical candidate payload is a verified no-op and preserves that provenance.

## Native evidence

All production calls remain MATLAB -> existing .NET 8 DLLs. Official `setup-matlab@v3` / `run-command@v3` use the proven public-project route. Native preflight runs the existing wrapper/CLI CI entrypoint and records all ten scenario IDs and results; canonical assertions are unchanged. Wrapper and CLI source SHAs, native suite digest, artifact tuple, projection digest, workflow/run identity, and summary hash are bound in evidence. Platform jobs are independent, required successes. macOS BLE remains explicitly unsupported by the current Core payload. No hardware operation or Python Engine is used.

The suite hash normalizes only CRLF to LF for MATLAB source identity; DLL/archive hashes always cover exact bytes. This does not change Git EOL policy or source files.

The receiver tests use synthetic files/API responses solely to test rejection gates, never as runtime conformance. No end-to-end candidate dispatch has been executed or claimed. Technical public CI success remains separate from support/licensing interpretation.

## Separate Core coordination patch

After setup/rulesets/App verification, add one MATLAB entry to Core's reviewed receiver map: repository `cwru-non-academic/Matlab_WSS_Integration_Lib`, workflow `promote-wss.yml`, ref `dev`, input `candidate_json` using the existing immutable universal producer tuple. Keep the current required producer jobs and exact inventory contract; do not accept a Core PR artifact, weaken provenance, or add the CLI directly to Core fan-out. Scope the dispatch token to MATLAB wrapper Actions-write only after producer validation. Coordinate this change with the active Core macOS work; do not publish or activate it concurrently from this task.

## Canonical Core 27-file preparation

The canonical tuple in `automation/candidates/core-40794719291.json` identifies Core dev push `25ee25e519e77be96a918b9b63f3a402c550d631`, run `40794719291`, artifact `12863706436`. No candidate download or dispatch is implied by recording it.

New candidates must contain exactly 27 producer files, including `backends/macos/WSS.Transport.BLE.MacOS.dll` and `backends/macos/libwss_macos_ble.dylib`. Only the explicitly recorded historical reference-copy bootstrap may retain its 25-file inventory. The producer guard additionally requires the universal macOS bridge build and both x86_64/arm64 macOS BLE consumer checks. The macOS compatibility path uses Core's explicit registration and load-only ABI verification; no Bluetooth initialization, authorization probe, scan or connection is performed. Legacy committed payloads remain identified as legacy, not mistaken for the new candidate.

`candidate_preflight_ready` is a separate, currently false, test-only gate. `baseline_ready` remains false and promotion still additionally requires the repository enable variable. This avoids requiring deployment approval before the first candidate can be tested. Any future flag change requires review and an announced test; no setting or credential change is included here.

Before dispatch: verify this contract on ordinary CI, register the updated disabled workflow on default main, verify existing App read access and rulesets, and obtain approval for one correlated pair of wrapper/CLI preflight runs using exact current dev source SHAs. Inspect existing correlated runs before any retry. Successful Python acceptance is not MATLAB evidence. Full promotion remains held until the native MATLAB candidate proof is reviewed.
