import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
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
  const engine=readFileSync('.github/scripts/wss-ci/receipt.mjs','utf8');
  assert.match(engine,/from '\.\/verify\.mjs'/);
  assert.match(engine,/loadPlan.*from '\.\/github\.mjs'/);
});


test('retired receipt launcher fails closed without invoking another engine',()=>{
  const launcher=new URL('../Write-ReleaseReceipt.mjs',import.meta.url);
  const source=readFileSync(launcher,'utf8');
  assert.doesNotMatch(source,/runReceipt|import\s|require\s*\(|spawn|exec/);
  const result=spawnSync(process.execPath,[fileURLToPath(launcher)],{encoding:'utf8'});
  assert.equal(result.status,1);
  assert.match(result.stderr,/Legacy receipt launcher is retired/);
});

test('receipt workflow directly invokes the immutable common engine',()=>{
  const workflow=readFileSync(new URL('../../workflows/release-receipt.yml',import.meta.url),'utf8');
  assert.doesNotMatch(workflow,/Invoke-ReleaseReceipt\.ps1|Write-ReleaseReceipt\.mjs/);
  assert.match(workflow,/bootstrap\/Python_WSS_Integration_Lib/);
  assert.match(workflow,/& node \(Join-Path \$config\.engineRoot '\.github\/scripts\/wss-ci\/receipt\.mjs'\)/);
});
