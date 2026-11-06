import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as verifier from '../wss-ci/verify.mjs';
import * as transport from '../wss-ci/github.mjs';
import {targetPolicy} from '../ReceiptGuards.mjs';

test('the actual copied receipt verifier loads and agrees with both MATLAB policies',()=>{
  const lock=JSON.parse(readFileSync('.github/scripts/wss-ci.lock.json','utf8'));
  assert.match(lock.source_commit,/^[a-f0-9]{40}$/);
  for(const name of ['producer','jobs','candidate','canonical','bytesDigest']) assert.equal(typeof verifier[name],'function');
  for(const name of ['GitHub','loadPlan','archive']) assert.equal(typeof transport[name],'function');
  const profiles=JSON.parse(readFileSync('.github/scripts/wss-ci/receipt-targets.json','utf8'));
  const manifest={schema:'wss-required-targets/v1',channel:'dev',release_kind:'beta',stable_enabled:false,excluded:[],targets:Object.values(profiles).map(p=>p.target)};
  verifier.manifest(manifest);
  assert.equal(manifest.targets.length,9);
  for(const id of ['matlab-wrapper','matlab-cli']) assert.equal(targetPolicy({channel:'dev',manifest},id).id,id);
  for(const job of ['BLE Consumer for Windows','BLE Consumer for Linux','BLE Consumer for Mac']) assert.ok(verifier.CORE_JOBS.includes(job));
  assert.match(readFileSync('.github/scripts/Write-ReleaseReceipt.mjs','utf8'),/runReceipt.*wss-ci\/receipt\.mjs/);
  const engine=readFileSync('.github/scripts/wss-ci/receipt.mjs','utf8');
  assert.match(engine,/from '\.\/verify\.mjs'/);
  assert.match(engine,/loadPlan.*from '\.\/github\.mjs'/);
});
