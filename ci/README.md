# Native CI

## Native unit-test source contract

`native-test-contract.json` lists the exact test IDs discovered by MATLAB for
this product source. Update it alongside intentional test additions/removals.
The runner checks exact discovered and completed IDs, rejects duplicates, and
requires every result to pass without skips. Evidence includes these IDs and
results; counts alone cannot satisfy a new-source contract.

MATLAB binders retrieve the contract from the verified immutable product-owner
revision, independently of the tooling checkout. Historical sources without a
manifest are accepted only for a frozen reviewed tests-tree and native-runner
blob pair with an authenticated discovery inventory. Unknown historical pairs
fail closed. These compatibility entries are not moving branch or package pins.
Canonical Core scenarios, payload hashes and source/native evidence remain
mandatory and separate from this unit-test inventory.
