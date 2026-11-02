import test from 'node:test';
import assert from 'node:assert/strict';
import {TARGETS,targetPolicy,readOnlyGh,normalRun,changedHead,mergedPr,emitter} from '../ReceiptGuards.mjs';
const sha='a'.repeat(40),before='b'.repeat(40),hash='c'.repeat(64);
const target=id=>({id,...structuredClone(TARGETS[id]),branch:'dev'});
const policy=id=>({channel:'dev',manifest:{channel:'dev',targets:[target(id)],excluded:[]}});
test('current explicitly excluded MATLAB targets cannot produce receipts',()=>{
  const p=policy('matlab-wrapper');p.manifest.excluded=[{id:'matlab-wrapper',dispatch:false}];
  assert.throws(()=>targetPolicy(p,'matlab-wrapper'),/excluded/);
});
test('target policy preserves all required jobs, trusted paths and parents',()=>{
  assert.equal(targetPolicy(policy('matlab-cli'),'matlab-cli').role,'cli');
  const p=policy('matlab-cli');p.manifest.targets[0].jobs.pop();assert.throws(()=>targetPolicy(p,'matlab-cli'));
  const q=policy('matlab-cli');q.manifest.targets[0].trusted_paths.pop();assert.throws(()=>targetPolicy(q,'matlab-cli'));
  const r=policy('matlab-cli');r.manifest.targets[0].parents={};assert.throws(()=>targetPolicy(r,'matlab-cli'));
});
test('transport rejects mutation and caller-supplied command options',()=>{
  readOnlyGh(['api','repos/cwru-non-academic/WSSCore/actions/runs/1']);
  assert.throws(()=>readOnlyGh(['api','--method','POST','repos/cwru-non-academic/WSSCore']));
  assert.throws(()=>readOnlyGh(['pr','merge','1']));
  assert.throws(()=>readOnlyGh(['api','repos/other/repo']));
});
test('no-op and preparation-only states cannot impersonate a reviewed dependency merge',()=>{
  assert.throws(()=>changedHead(sha,{head_sha:sha}));changedHead(sha,{head_sha:before});
  const t=target('matlab-wrapper'),p={merged:true,state:'closed',merge_commit_sha:sha,merged_by:{type:'User'},user:{type:'Bot'},base:{ref:'dev',repo:{full_name:t.repository}},head:{repo:{full_name:t.repository},ref:`automation/matlab-wss-1-${hash}`}};
  mergedPr(p,t,sha,{run_id:'1',sha256:hash});
  assert.throws(()=>mergedPr({...p,user:{type:'User'}},t,sha,{run_id:'1',sha256:hash}));
  assert.throws(()=>mergedPr({...p,auto_merge:{}},t,sha,{run_id:'1',sha256:hash}));
});
test('fresh actual-merge normal proof rejects PR checkout and failed superseding run',()=>{
  const t=target('matlab-wrapper'),p={merge_commit_sha:sha,merged_at:'2026-10-29T00:00:00Z'};
  const r={id:1,run_attempt:1,event:'workflow_dispatch',head_sha:sha,head_branch:'dev',repository:{full_name:t.repository},head_repository:{full_name:t.repository},path:t.workflow,created_at:'2026-10-29T00:01:00Z',status:'completed',conclusion:'success'};
  assert.equal(normalRun([r],t,p).id,1);assert.throws(()=>normalRun([{...r,event:'pull_request'}],t,p));
  assert.throws(()=>normalRun([r,{...r,id:2,conclusion:'failure'}],t,p));
});
test('receipt emitter must be the exact current dev run and attempt',()=>{
  const t=target('matlab-cli'),env={GITHUB_ACTIONS:'true',GITHUB_REPOSITORY:t.repository,GITHUB_REF:'refs/heads/dev',GITHUB_SHA:sha,GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_RUN_ID:'1',GITHUB_RUN_ATTEMPT:'1'};
  const r={id:1,run_attempt:1,repository:{full_name:t.repository},head_repository:{full_name:t.repository},head_sha:sha,head_branch:'dev',event:'workflow_dispatch',path:'.github/workflows/release-receipt.yml'};
  emitter(r,env,t,sha);assert.throws(()=>emitter({...r,run_attempt:2},env,t,sha));assert.throws(()=>emitter(r,{...env,GITHUB_REF:'refs/heads/main'},t,sha));
});
