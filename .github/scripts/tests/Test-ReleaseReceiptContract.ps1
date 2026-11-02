# Pure receipt contract fixtures only; no GitHub calls or live receipt output.
. "$PSScriptRoot/../ReleaseReceiptContract.ps1"
function Reject-Receipt([scriptblock]$Action) { $rejected=$false;try { & $Action } catch { $rejected=$true };if (!$rejected) { throw 'Expected receipt contract rejection.' } }
$wrapper=('a'*40);$cli=('b'*40)
$approval=[pscustomobject]@{wrapper=[pscustomobject]@{source_sha=$wrapper};cli=[pscustomobject]@{source_sha=$cli}}
$plan=[pscustomobject]@{target_snapshots=[pscustomobject]@{'matlab-wrapper'=[pscustomobject]@{head_sha=$wrapper};'matlab-cli'=[pscustomobject]@{head_sha=$cli}}}
Assert-MatlabReceiptSnapshots $approval $plan
$plan.target_snapshots.'matlab-cli'.head_sha=('c'*40)
Reject-Receipt { Assert-MatlabReceiptSnapshots $approval $plan }
$marker=Get-MatlabApplicationPreflightMarker 'cli' $wrapper $cli '123'
$record=Read-MatlabReceiptApplicationMarker $marker 'cli'
if ($record.wrapper_sha -cne $wrapper -or $record.cli_sha -cne $cli -or [string]$record.preflight_run_id -cne '123') { throw 'Actual merged-wrapper marker differs.' }
Reject-Receipt { Read-MatlabReceiptApplicationMarker ($marker+"`n"+$marker) 'cli' }
Reject-Receipt { Read-MatlabReceiptApplicationMarker '' 'cli' }
Reject-Receipt { Invoke-MatlabGh @('api','--method','POST','repos/cwru-non-academic/WSSCore/actions/workflows/artifacts.yml/dispatches') }
Reject-Receipt { Invoke-MatlabGh @('pr','merge','1') }
Write-Output 'PASS frozen paired sources, canonical merged-wrapper marker and read-only receipt contracts. No live proof emitted.'
