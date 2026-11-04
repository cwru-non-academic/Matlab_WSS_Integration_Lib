import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {CONTRACT_SHA,targetPolicy} from '../ReceiptGuards.mjs';

test('immutable Core verifier loads and agrees with both MATLAB receiver policies',async()=>{
  assert.ok(process.env.RECEIPT_CORE_ROOT,'Hosted CI must supply the checked-out Core contract');
  const root=resolve(process.env.RECEIPT_CORE_ROOT);
  const sha=execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim();
  assert.equal(sha,CONTRACT_SHA);
  const verifier=await import(pathToFileURL(join(root,'tools/release/verify.mjs')));
  const transport=await import(pathToFileURL(join(root,'tools/release/github.mjs')));
  for(const name of ['producer','jobs','candidate','canonical','bytesDigest']) assert.equal(typeof verifier[name],'function');
  for(const name of ['GitHub','loadPlan','archive']) assert.equal(typeof transport[name],'function');
  const manifest=JSON.parse(readFileSync(join(root,'tools/release/targets.dev.json'),'utf8'));
  verifier.manifest(manifest);
  assert.equal(manifest.targets.length,9);
  assert.deepEqual(manifest.excluded,[]);
  for(const id of ['matlab-wrapper','matlab-cli']) assert.equal(targetPolicy({channel:'dev',manifest},id).id,id);
  const workflow=readFileSync('.github/workflows/release-receipt.yml','utf8');
  assert.match(workflow,new RegExp(`repository: cwru-non-academic/WSSCore\\r?\\n\\s+ref: ${CONTRACT_SHA}\\r?\\n`));
});
