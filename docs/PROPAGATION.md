# Future Core and application propagation

Core propagation remains inactive. Ordinary PR CI is separate and documented in
`ci/README.md`; there are no Core promotion or dispatch handlers.
`automation/pipeline-contract.json`
records the intended ownership boundary; adding GitHub App access alone must not
activate it.

1. Core publishes an immutable artifact with source revision, manifest and hashes.
2. The wrapper verifies that artifact, updates its owned `Cs_Libraries/` payload,
   builds its managed host and executes MATLAB checks and the canonical emulator
   scenarios against the candidate payload.
3. Successful evidence supports a wrapper `dev` pull request. A human reviews and
   merges it; promotion to `main` remains explicit.
4. The CLI validates its production factory, argument/command routing, cleanup
   and canonical scenarios against the merged wrapper revision.
5. A successful consumer update proposes a CLI `dev` pull request whose update is
   only the pinned wrapper gitlink. A human reviews and merges it. Do not copy
   wrapper implementation or Core payload into the CLI.

Before enabling any dispatch: grant the intended GitHub App access to both repos;
confirm branch/protection conventions; provide a licensed supported MATLAB
runner and matching CLR; prove conformance and busy/input ticking; bind artifact
hashes and exact wrapper/CLI source revisions to evidence; retain human merge
gates. No Core fan-out configuration is changed by this setup.

The CLI pins a published wrapper commit. Changes in a sibling development
checkout are never represented implicitly by that gitlink; use the explicit
`--wrapper-root` override only for deliberate local development. Wrapper commits
must be published before a consumer update can pin them. No commit or push is
performed by the CLI or test tools.
