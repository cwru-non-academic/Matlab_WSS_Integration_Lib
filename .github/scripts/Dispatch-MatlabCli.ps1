param([ValidateSet('cli')][string]$Role='cli',[Parameter(Mandatory)][string]$EventPath,[Parameter(Mandatory)][string]$WorkRoot,[switch]$ValidateOnly)
. "$PSScriptRoot/MatlabPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne $MatlabWrapperRepository) { throw 'Trusted wrapper dispatcher required.' }
$application=Get-MatlabApplication $Role
$event=Get-Content -LiteralPath $EventPath -Raw | ConvertFrom-Json
$pr=$event.pull_request
Assert-MatlabHumanMerge $pr
if (!$pr.merged -or $pr.base.ref -cne 'dev' -or $pr.head.repo.full_name -cne $MatlabWrapperRepository -or $pr.user.type -cne 'Bot' -or $pr.head.ref -cnotlike 'automation/matlab-wss-*') { throw 'Not a reviewed Matlab dependency promotion.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Dispatcher workspace must be new.' }
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
$approval=Read-MatlabApprovalMarker $pr.body (Join-Path $WorkRoot 'approval.json')
if ($pr.head.ref -cne "automation/matlab-wss-$($approval.candidate.run_id)-$($approval.candidate.sha256)") { throw 'Promotion branch/candidate mismatch.' }
$config=Read-MatlabConfig "$PSScriptRoot/../matlab-ci.json"
if (!$config.baseline_ready -or $config.automated_execution -cne 'matlab-native') { throw 'Approved .NET promotion baseline required.' }
Assert-MatlabApproval $approval (Join-Path $WorkRoot 'evidence') $config
Assert-MatlabMergedWrapper $pr.merge_commit_sha ([string]$pr.number) $approval
$body=@{ref='dev';inputs=@{wrapper_sha=$pr.merge_commit_sha;wrapper_pr=[string]$pr.number;approval_json=($approval | ConvertTo-Json -Depth 8 -Compress)}} | ConvertTo-Json -Depth 6 -Compress
$pages=Invoke-MatlabGh @('api','--paginate','--slurp',"repos/$($application.repository)/actions/workflows/promote-integration.yml/runs?event=workflow_dispatch&per_page=100") | ConvertFrom-Json
$existing=@($pages | ForEach-Object { $_.workflow_runs } | Where-Object { $_.display_title -ceq "Promote Integration $($pr.merge_commit_sha) / wss-$($approval.candidate.run_id)-$($approval.candidate.artifact_id)" })
if ($existing.Count -gt 1) { throw 'Ambiguous prior application dispatch; inspect manually.' }
if ($existing.Count -eq 1 -and $existing[0].status -ceq 'completed' -and $existing[0].conclusion -cne 'success') { throw "Prior correlated application promotion failed: $($existing[0].html_url). Inspect before replay." }
if ($existing.Count -eq 1) { 'dispatch_needed=false' >> $env:GITHUB_OUTPUT; Write-Output 'Prior correlated application promotion exists; no redispatch.'; exit 0 }
[IO.File]::WriteAllText((Join-Path $WorkRoot ($Role+'-dispatch.json')),$body)
'dispatch_needed=true' >> $env:GITHUB_OUTPUT
if ($ValidateOnly) { exit 0 }
if (!$env:MATLAB_DISPATCH_TOKEN) { throw 'Scoped target-only application Actions-write token required after validation.' }
$readToken=$env:GH_TOKEN
try {
    $env:GH_TOKEN=$env:MATLAB_DISPATCH_TOKEN
    $body | & gh api --method POST "repos/$($application.repository)/actions/workflows/promote-integration.yml/dispatches" --input -
    if ($LASTEXITCODE -ne 0) { throw 'Application dispatch failed/uncertain; inspect before retrying.' }
} finally { $env:GH_TOKEN=$readToken }
