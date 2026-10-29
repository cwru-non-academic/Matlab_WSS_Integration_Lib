export const WRAPPER='cwru-non-academic/Matlab_WSS_Integration_Lib';
export const CONTRACT_SHA='0fb9ae74504e03dc63777ed70a6ec51c4369d5ab';
export const RECEIPT_WORKFLOW='.github/workflows/release-receipt.yml';
const paths=workflow=>['.github/workflows/release-receipt.yml','.github/scripts',workflow,'.github/actions','.github/matlab-ci.json','ci','conformance'];
export const TARGETS={
  'matlab-wrapper':{role:'wrapper',kind:'payload',repository:WRAPPER,workflow:'.github/workflows/wss-compatibility.yml',parents:{},
    jobs:['Integration behavioral tests',...['Windows','Ubuntu','macOS'].map(p=>`Integration compatibility (${p})`)],coverage:['canonical-conformance','packaged-macos-ble-load'],trusted_paths:paths('.github/workflows/wss-compatibility.yml')},
  'matlab-cli':{role:'cli',kind:'gitlink',repository:'cwru-non-academic/CLI_Matlab_WSS_Application',workflow:'.github/workflows/cli-ci.yml',parents:{'matlab-wrapper':'external/wss-matlab-wrapper'},
    jobs:['CLI general conformance',...['Windows','Ubuntu','macOS'].map(p=>`CLI platform compatibility (${p})`)],coverage:['canonical-conformance','packaged-macos-ble-load'],trusted_paths:paths('.github/workflows/cli-ci.yml')}
};
export function need(value,message) { if(!value) throw new Error(message); }
export const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
export function readOnlyGh(args) {
  need((args.length===2 && args[0]==='api' && /^repos\/cwru-non-academic\//.test(args[1])) ||
    (args[0]==='run' && args[1]==='download' && /^\d+$/.test(args[2]) && args.length===9 && args[3]==='--repo' && args[5]==='--name' && args[7]==='--dir'),
    'Receipt transport permits only GitHub GET and artifact download');
}
export function targetPolicy(p,id) {
  need(p.channel==='dev' && p.manifest?.channel==='dev','Only dev acceptance is prepared');
  need(!(p.manifest.excluded||[]).some(t=>t.id===id),'MATLAB remains excluded by the frozen release policy');
  const expected=TARGETS[id],actual=p.manifest.targets.filter(t=>t.id===id);
  need(expected && actual.length===1,'Unknown/ambiguous Matlab target');
  const t=actual[0];
  need(t.repository===expected.repository && t.branch==='dev' && t.workflow===expected.workflow && t.kind===expected.kind &&
    same([...t.jobs].sort(),[...expected.jobs].sort()) && same(t.parents,expected.parents) &&
    same([...t.coverage].sort(),[...expected.coverage].sort()) && same([...(t.trusted_paths||[])].sort(),[...expected.trusted_paths].sort()),'Frozen target differs from receiver-owned required checks/parents/coverage');
  return {...t,role:expected.role};
}
export function runIdentity(r,repo,workflow,sha,event) {
  need(r.repository?.full_name===repo && r.head_repository?.full_name===repo && r.path===workflow &&
    r.head_sha===sha && r.head_branch==='dev' && r.event===event,'Run source/repository/workflow/channel mismatch');
}
export function normalRun(runs,t,pr) {
  const eligible=runs.filter(r=>['push','workflow_dispatch'].includes(r.event) && r.head_sha===pr.merge_commit_sha &&
    r.head_branch==='dev' && r.repository?.full_name===t.repository && r.head_repository?.full_name===t.repository && r.path===t.workflow &&
    Date.parse(r.created_at)>=Date.parse(pr.merged_at)).sort((a,b)=>Number(b.id)-Number(a.id));
  need(eligible.length>0 && eligible[0].status==='completed' && eligible[0].conclusion==='success','Latest actual-merge normal CI is missing/pending/failed');
  need(/^[1-9][0-9]*$/.test(String(eligible[0].id)) && Number.isSafeInteger(eligible[0].run_attempt) && eligible[0].run_attempt>=1,'Normal CI run/attempt is invalid');
  return eligible[0];
}
export function changedHead(head,snapshot) {
  need(/^[a-f0-9]{40}$/.test(head) && /^[a-f0-9]{40}$/.test(snapshot.head_sha) && head!==snapshot.head_sha,
    'No-op/preparation-only receipt is not supported; a real reviewed dependency merge is required');
}
export function mergedPr(pr,t,head,candidate) {
  need(pr.merged===true && pr.state==='closed' && pr.merge_commit_sha===head && pr.merged_by?.type==='User' &&
    !pr.auto_merge && pr.user?.type==='Bot' && pr.base?.ref==='dev' && pr.base?.repo?.full_name===t.repository &&
    pr.head?.repo?.full_name===t.repository && pr.head.ref===`automation/matlab-wss-${candidate.run_id}-${candidate.sha256}`,
    'Receipt requires the actual human-reviewed same-repository bot dependency merge');
}
export function emitter(r,env,t,head) {
  need(env.GITHUB_ACTIONS==='true' && env.GITHUB_REPOSITORY===t.repository && env.GITHUB_REF==='refs/heads/dev' &&
    env.GITHUB_SHA===head && env.GITHUB_EVENT_NAME==='workflow_dispatch','Receipt must execute at actual accepted dev source');
  runIdentity(r,t.repository,RECEIPT_WORKFLOW,head,'workflow_dispatch');
  need(String(r.id)===env.GITHUB_RUN_ID && Number.isSafeInteger(r.run_attempt) && r.run_attempt===Number(env.GITHUB_RUN_ATTEMPT), 'Emitter run/attempt mismatch');
}
