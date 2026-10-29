. "$PSScriptRoot/MatlabContract.ps1"

function Wait-MatlabRun([string]$Repository,[string]$RunId,[string]$Sha,[string]$Workflow,[string]$Event,[int]$TimeoutSeconds=2400) {
    Assert-MatlabSha $Sha
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $run=Invoke-MatlabGh @('api',"repos/$Repository/actions/runs/$RunId") | ConvertFrom-Json
        if ($run.repository.full_name -cne $Repository -or $run.path -cne ".github/workflows/$Workflow" -or $run.head_sha -cne $Sha -or $run.event -cne $Event) { throw 'Workflow run identity mismatch.' }
        if ($run.status -ceq 'completed') {
            if ($run.conclusion -cne 'success') { throw 'Required workflow did not succeed; never substitute another green run.' }
            return $run
        }
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Timed out waiting for exact workflow.' }
        Start-Sleep -Seconds 15
    } while ($true)
}

function Assert-MatlabProducer($Candidate) {
    Assert-MatlabCandidate $Candidate
    $run=Wait-MatlabRun $Candidate.repository $Candidate.run_id $Candidate.commit 'artifacts.yml' 'push'
    if ($run.head_branch -cne 'dev' -or $run.head_repository.full_name -cne $Candidate.repository -or $Candidate.archive -cne 'WSS-Universal-ci.zip') { throw 'Automatic Matlab propagation requires the canonical Core dev push archive.' }
    $compare=Invoke-MatlabGh @('api',"repos/$($Candidate.repository)/compare/$($Candidate.commit)...dev") | ConvertFrom-Json
    if ($compare.status -cnotin @('ahead','identical')) { throw 'Producer commit is not contained in Core dev.' }
    $pages=Invoke-MatlabGh @('api','--paginate','--slurp',"repos/$($Candidate.repository)/actions/runs/$($Candidate.run_id)/jobs?per_page=100&filter=latest") | ConvertFrom-Json
    $jobs=@($pages | ForEach-Object { $_.jobs })
    foreach ($name in @('Build and validate artifacts','Core conformance','Serial consumer (Windows)','Serial consumer (macOS)','Serial consumer (Linux)','BLE consumer (Windows)','BLE consumer (Linux)','Core consumer (Windows)','Core consumer (macOS)','Core consumer (Linux)','Start routine downstream validation')) {
        $matching=@($jobs | Where-Object { $_.name -ceq $name })
        if ($matching.Count -ne 1 -or $matching[0].conclusion -cne 'success') { throw "Required Core producer job missing/skipped/failed: $name" }
    }
    $artifact=Invoke-MatlabGh @('api',"repos/$($Candidate.repository)/actions/artifacts/$($Candidate.artifact_id)") | ConvertFrom-Json
    if ($artifact.expired -or $artifact.name -cne 'universal-release-assets' -or [string]$artifact.workflow_run.id -cne [string]$Candidate.run_id -or $artifact.workflow_run.head_sha -cne $Candidate.commit) { throw 'Wrong/expired producer artifact.' }
}

function Get-MatlabHead([string]$Repository) {
    $branch=Invoke-MatlabGh @('api',"repos/$Repository/branches/dev") | ConvertFrom-Json
    Assert-MatlabSha $branch.commit.sha
    $branch.commit.sha
}

function Start-MatlabPreflight([string]$Repository,$Candidate,[string]$WrapperSha,[string]$ApplicationSha,[switch]$NoWait) {
    Assert-MatlabCandidate $Candidate
    Assert-MatlabSha $WrapperSha
    Assert-MatlabSha $ApplicationSha
    if ($Repository -cnotin @($MatlabWrapperRepository,$MatlabCliRepository)) { throw 'Unknown Matlab preflight repository.' }
    $correlation="wss-$($Candidate.run_id)-$($Candidate.artifact_id)-$WrapperSha-$ApplicationSha"
    $title="WSS preflight $($Candidate.run_id) / $correlation"
    function Find-Run {
        $pages=Invoke-MatlabGh @('api','--paginate','--slurp',"repos/$Repository/actions/workflows/wss-preflight.yml/runs?event=workflow_dispatch&per_page=100") | ConvertFrom-Json
        $runs=@($pages | ForEach-Object { $_.workflow_runs } | Where-Object { $_.display_title -ceq $title })
        if ($runs.Count -gt 1) { throw 'Ambiguous correlated preflight; no run selection or redispatch.' }
        if ($runs.Count -eq 1) { return $runs[0] }
    }
    $found=Find-Run
    if (!$found) {
        $inputs=@{candidate_json=($Candidate | ConvertTo-Json -Depth 5 -Compress);wrapper_sha=$WrapperSha;correlation_id=$correlation}
        $sourceField='cli_sha'
        $inputs[$sourceField]=$ApplicationSha
        $body=@{ref='dev';inputs=$inputs} | ConvertTo-Json -Depth 5 -Compress
        if (!$env:MATLAB_PREFLIGHT_TOKEN) { throw 'Scoped downstream Actions-write token required.' }
        $readToken=$env:GH_TOKEN
        try {
            $env:GH_TOKEN=$env:MATLAB_PREFLIGHT_TOKEN
            $body | & gh api --method POST "repos/$Repository/actions/workflows/wss-preflight.yml/dispatches" --input -
            if ($LASTEXITCODE -ne 0) { throw 'Preflight dispatch failed/uncertain. Inspect before any retry.' }
        } finally { $env:GH_TOKEN=$readToken }
        $deadline=[DateTime]::UtcNow.AddSeconds(180)
        do {
            $found=Find-Run
            if ($found) { break }
            if ([DateTime]::UtcNow -ge $deadline) { throw 'Dispatched preflight not discovered; inspect before retrying.' }
            Start-Sleep -Seconds 5
        } while ($true)
    }
    $expectedSha=if ($Repository -ceq $MatlabWrapperRepository) { $WrapperSha } else { $ApplicationSha }
    if ($found.head_sha -cne $expectedSha) { throw 'Correlated preflight source changed; no automatic redispatch.' }
    if ($NoWait) { return $found }
    Wait-MatlabRun $Repository ([string]$found.id) $expectedSha 'wss-preflight.yml' 'workflow_dispatch'
}

function Read-MatlabApproval([string]$Path) {
    $value=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $roles=@(Get-MatlabApprovalRoles $value)
    Assert-MatlabCandidate $value.candidate
    foreach ($role in $roles) {
        Assert-MatlabSha $value.$role.source_sha
        if ([string]$value.$role.preflight_run_id -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid preflight run ID.' }
    }
    Assert-MatlabSha $value.fixture.commit
    if ($value.fixture.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $value.projection_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid evidence digest.' }
    $normalized=[ordered]@{
        schema=$value.schema
        candidate=[ordered]@{ repository=$value.candidate.repository; commit=$value.candidate.commit; run_id=[string]$value.candidate.run_id; artifact_id=[string]$value.candidate.artifact_id; archive=$value.candidate.archive; sha256=$value.candidate.sha256 }
        wrapper=[ordered]@{source_sha=$value.wrapper.source_sha;preflight_run_id=[string]$value.wrapper.preflight_run_id}
        cli=[ordered]@{source_sha=$value.cli.source_sha;preflight_run_id=[string]$value.cli.preflight_run_id}
    }
    $normalized.fixture=[ordered]@{commit=$value.fixture.commit;sha256=$value.fixture.sha256}
    $normalized.projection_sha256=$value.projection_sha256
    [pscustomobject]$normalized
}

function Get-MatlabApprovalMarker($Approval) {
    $null=Get-MatlabApprovalRoles $Approval
    $prefix=if ($Approval.schema -ceq 'wss-matlab-promotion/v2') { '<!-- wss-matlab-approval:v2 ' } else { '<!-- wss-matlab-approval:' }
    $prefix+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Approval | ConvertTo-Json -Depth 8 -Compress)))+' -->'
}

function Read-MatlabApprovalMarker([string]$Body,[string]$Destination) {
    $matches=[regex]::Matches($Body,'(?m)^<!-- wss-matlab-approval:(?:v2 )?([A-Za-z0-9+/=]+) -->\r?$')
    if ($matches.Count -ne 1 -or [regex]::Matches($Body,'<!-- wss-matlab-approval:').Count -ne 1) { throw 'Missing/ambiguous Matlab approval marker.' }
    [IO.File]::WriteAllText($Destination,[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($matches[0].Groups[1].Value)))
    $approval=Read-MatlabApproval $Destination
    if ((Get-MatlabApprovalMarker $approval) -cne $matches[0].Value.TrimEnd("`r")) { throw 'Noncanonical approval marker.' }
    $approval
}

function Assert-MatlabApproval($Approval,[string]$EvidenceRoot,$Config) {
    Assert-MatlabProducer $Approval.candidate
    foreach ($role in @(Get-MatlabApprovalRoles $Approval)) {
        $repo=if ($role -ceq 'wrapper') { $MatlabWrapperRepository } else { (Get-MatlabApplication $role).repository }
        $e=Get-MatlabEvidence $repo $Approval.$role.preflight_run_id $Approval.$role.source_sha $role $Approval.candidate (Join-Path $EvidenceRoot $role) $Config
        $pairRole='cli'
        $sourceField=(Get-MatlabApplication $pairRole).source_field
        if ($e.wrapper_sha -cne $Approval.wrapper.source_sha -or $e.$sourceField -cne $Approval.$pairRole.source_sha -or
            $e.projection_sha256 -cne $Approval.projection_sha256 -or $e.fixture_sha -cne $Approval.fixture.commit -or
            $e.fixture_sha256 -cne $Approval.fixture.sha256) { throw 'Preflights did not test the approved source/candidate tuple.' }
    }
}

function Assert-MatlabMergedApplicationPreflight($Approval,[ValidateSet('cli')][string]$Role,[string]$WrapperSha,[string]$ApplicationSha,[string]$RunId,[string]$Root,$Config) {
    Assert-MatlabSha $WrapperSha
    Assert-MatlabSha $ApplicationSha
    if ($RunId -cnotmatch '^[1-9][0-9]*$') { throw 'Exact merged-wrapper application preflight ID required.' }
    $application=Get-MatlabApplication $Role
    $e=Get-MatlabEvidence $application.repository $RunId $ApplicationSha $Role $Approval.candidate $Root $Config
    if ($e.wrapper_sha -cne $WrapperSha -or $e.($application.source_field) -cne $ApplicationSha -or $e.projection_sha256 -cne $Approval.projection_sha256 -or
        $e.fixture_sha -cne $Approval.fixture.commit -or $e.fixture_sha256 -cne $Approval.fixture.sha256) { throw 'Application preflight did not test the exact accepted merged wrapper and current application source.' }
}

function Assert-MatlabMergedCliPreflight($Approval,[string]$WrapperSha,[string]$CliSha,[string]$RunId,[string]$Root,$Config) {
    Assert-MatlabMergedApplicationPreflight $Approval 'cli' $WrapperSha $CliSha $RunId $Root $Config
}

function Get-MatlabApplicationPreflightMarker([ValidateSet('cli')][string]$Role,[string]$WrapperSha,[string]$ApplicationSha,[string]$RunId) {
    Assert-MatlabSha $WrapperSha
    Assert-MatlabSha $ApplicationSha
    if ($RunId -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid application preflight ID.' }
    $record=[ordered]@{wrapper_sha=$WrapperSha}
    $record[(Get-MatlabApplication $Role).source_field]=$ApplicationSha
    $record.preflight_run_id=$RunId
    '<!-- wss-matlab-'+$Role+'-preflight:v1 '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Compress)))+' -->'
}

function Get-MatlabCliPreflightMarker([string]$WrapperSha,[string]$CliSha,[string]$RunId) {
    Get-MatlabApplicationPreflightMarker 'cli' $WrapperSha $CliSha $RunId
}

function Assert-MatlabRemoteProjection([string]$Sha,$Record) {
    Assert-MatlabSha $Sha
    if ($Record.schema -cne 'wss-matlab-projection/v1' -or (Get-MatlabProjectionDigest $Record.files) -cne $Record.projection_sha256 -or
        @(Compare-Object $MatlabProjectionFiles @($Record.files.source) -CaseSensitive).Count) { throw 'Invalid merged projection inventory/digest.' }
    $tree=Invoke-MatlabGh @('api',"repos/$MatlabWrapperRepository/git/trees/${Sha}?recursive=1") | ConvertFrom-Json
    if ($tree.truncated) { throw 'Merged wrapper tree response is truncated.' }
    $actual=@($tree.tree | Where-Object { $_.type -ceq 'blob' -and $_.path.StartsWith($MatlabPluginPath+'/',[StringComparison]::Ordinal) } | ForEach-Object { $_.path })
    $expected=@($MatlabProjectionFiles | ForEach-Object { "$MatlabPluginPath/$_" }) + @("$MatlabPluginPath/payload-source.json")
    if (@(Compare-Object $expected $actual -CaseSensitive).Count) { throw 'Merged wrapper payload inventory differs.' }
    foreach ($file in $Record.files) {
        $path="$MatlabPluginPath/$($file.source)"
        $entries=@($tree.tree | Where-Object { $_.path -ceq $path -and $_.type -ceq 'blob' })
        if ($entries.Count -ne 1) { throw 'Merged payload path missing/ambiguous.' }
        $blob=Invoke-MatlabGh @('api',"repos/$MatlabWrapperRepository/git/blobs/$($entries[0].sha)") | ConvertFrom-Json
        if ($blob.encoding -cne 'base64') { throw 'Unsupported blob encoding.' }
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Convert]::FromBase64String($blob.content))).ToLowerInvariant()
        if ($hash -cne $file.sha256) { throw "Actual merged payload differs: $path" }
    }
}


function Assert-MatlabMergedWrapper([string]$Sha,[string]$PrNumber,$Approval) {
    Assert-MatlabSha $Sha
    if ($PrNumber -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid wrapper PR number.' }
    $pr=Invoke-MatlabGh @('api',"repos/$MatlabWrapperRepository/pulls/$PrNumber") | ConvertFrom-Json
    Assert-MatlabHumanMerge $pr
    if (!$pr.merged -or $pr.merge_commit_sha -cne $Sha -or $pr.base.ref -cne 'dev' -or $pr.base.repo.full_name -cne $MatlabWrapperRepository -or
        $pr.head.repo.full_name -cne $MatlabWrapperRepository -or $pr.user.type -cne 'Bot') { throw 'Wrapper must be the actual reviewed same-repository bot PR merge into dev.' }
    if ($pr.head.ref -cne "automation/matlab-wss-$($Approval.candidate.run_id)-$($Approval.candidate.sha256)") { throw 'Merged wrapper PR is not the canonical candidate branch.' }
    $compare=Invoke-MatlabGh @('api',"repos/$MatlabWrapperRepository/compare/${Sha}...dev") | ConvertFrom-Json
    if ($compare.status -cnotin @('ahead','identical')) { throw 'Wrapper merge is not contained in dev.' }
    $delta=Invoke-MatlabGh @('api',"repos/$MatlabWrapperRepository/compare/$($Approval.wrapper.source_sha)...$Sha") | ConvertFrom-Json
    if ($delta.total_commits -lt 1 -or $delta.files.Count -ge 300) { throw 'Wrapper comparison empty or potentially truncated.' }
    Assert-MatlabDiff @($delta.files.filename) (Get-MatlabAllowedWrapperPaths)
    $pages=Invoke-MatlabGh @('api','--paginate','--slurp',"repos/$MatlabWrapperRepository/actions/workflows/wss-compatibility.yml/runs?event=pull_request&head_sha=$($pr.head.sha)&per_page=100") | ConvertFrom-Json
    $runs=@($pages | ForEach-Object { $_.workflow_runs } | Where-Object { @($_.pull_requests.number) -contains [int]$PrNumber } | Sort-Object { [long]$_.id } -Descending)
    if ($runs.Count -eq 0 -or $runs[0].status -cne 'completed' -or $runs[0].conclusion -cne 'success') { throw 'Latest final-head normal wrapper PR CI has not succeeded.' }
    $jobs=Invoke-MatlabGh @('api','--paginate','--slurp',"repos/$MatlabWrapperRepository/actions/runs/$($runs[0].id)/jobs?per_page=100") | ConvertFrom-Json
    foreach ($name in @('Integration behavioral tests','Integration compatibility (Windows)','Integration compatibility (Ubuntu)','Integration compatibility (macOS)')) {
        $required=@($jobs | ForEach-Object { $_.jobs } | Where-Object { $_.name -ceq $name })
        if ($required.Count -ne 1 -or $required[0].conclusion -cne 'success') { throw "Normal committed-state acceptance missing/skipped/failed: $name" }
    }
    $content=Invoke-MatlabGh @('api',"repos/$MatlabWrapperRepository/contents/.github/matlab-candidate.json?ref=$Sha") | ConvertFrom-Json
    $record=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($content.content)) | ConvertFrom-Json
    Assert-MatlabSameCandidate $record.candidate $Approval.candidate
    if ($record.projection_sha256 -cne $Approval.projection_sha256) { throw 'Merged projection differs from preflights.' }
    Assert-MatlabRemoteProjection $Sha $record
    $marker=Get-MatlabApprovalMarker $Approval
    if (!(($pr.body -split "`r?`n") -ccontains $marker)) { throw 'Merged PR does not carry the exact approval.' }
}


function Assert-MatlabSource([string]$Root,[string]$Sha,[switch]$IgnoreSubmodule) {
    Assert-MatlabSha $Sha
    if ((Invoke-MatlabGit $Root @('rev-parse','HEAD')).Trim() -cne $Sha) { throw 'Checked-out source differs from the pinned SHA.' }
    $statusArguments=@('status','--porcelain','--untracked-files=normal')
    if ($IgnoreSubmodule) { $statusArguments+='--ignore-submodules=all' }
    if (@(Invoke-MatlabGit $Root $statusArguments).Count -ne 0) { throw 'Source checkout must be clean before staging the disposable harness.' }
}

function Get-MatlabAllowedWrapperPaths {
    @($MatlabProjectionFiles | ForEach-Object { "$MatlabPluginPath/$_" }) + @('.github/matlab-candidate.json')
}

function Assert-MatlabDiff([string[]]$Paths,[string[]]$Allowed) {
    if ($Paths.Count -eq 0 -or @($Paths | Where-Object { $_ -cnotin $Allowed }).Count -gt 0) { throw 'Empty or out-of-scope promotion diff.' }
}

function Assert-MatlabHumanMerge($PullRequest) {
    if (!$PullRequest.merged -or !$PullRequest.merged_by -or $PullRequest.merged_by.type -cne 'User' -or
        !$PullRequest.merged_by.login -or $PullRequest.merged_by.login -cmatch '\[bot\]$' -or $PullRequest.auto_merge) { throw 'A recorded non-bot user merge with no auto-merge configuration is required.' }
}
function Assert-MatlabForwardCandidate($Current,$Incoming,[string]$ProjectionDigest) {
    Assert-MatlabCandidate $Incoming
    if ($Current.bootstrap_reference) {
        if ((Get-MatlabHead 'cwru-non-academic/WSSCore') -cne $Incoming.commit) { throw 'Reference-copy bootstrap requires the current canonical Core dev head; no older first candidate.' }
        return
    }
    Assert-MatlabCandidate $Current.candidate
    if ($Current.candidate.commit -ceq $Incoming.commit) {
        if ($Current.projection_sha256 -cne $ProjectionDigest) { throw 'Conflicting payload for the same Core commit.' }
        return
    }
    $comparison=Invoke-MatlabGh @('api',"repos/cwru-non-academic/WSSCore/compare/$($Current.candidate.commit)...$($Incoming.commit)") | ConvertFrom-Json
    if ($comparison.status -cne 'ahead') { throw 'Older or conflicting Core candidate would roll back the recorded dependency.' }
}
function Get-MatlabApprovalRoles($Approval) {
    if ($Approval.schema -cne 'wss-matlab-promotion/v1') { throw 'Unsupported MATLAB approval schema.' }
    @('wrapper','cli')
}
function Assert-MatlabFanoutApproval($Approval) {
    $null=Get-MatlabApprovalRoles $Approval
    foreach ($role in @('wrapper','cli')) {
        Assert-MatlabSha $Approval.$role.source_sha
        if ([string]$Approval.$role.preflight_run_id -cnotmatch '^[1-9][0-9]*$') { throw 'Both source-bound native preflight IDs required.' }
    }
}
function Get-MatlabDispatchApplications($Approval) {
    Assert-MatlabFanoutApproval $Approval
    Get-MatlabApplication 'cli'
}
function New-MatlabFanoutApproval($Candidate,[string]$WrapperSha,[string]$CliSha,$Config) {
    $sources=[ordered]@{wrapper=@{repository=$MatlabWrapperRepository;sha=$WrapperSha};cli=@{repository=$MatlabCliRepository;sha=$CliSha}}
    $runs=@{}; $failures=[Collections.Generic.List[string]]::new()
    foreach ($role in $sources.Keys) {
        try { $runs[$role]=Start-MatlabPreflight $sources[$role].repository $Candidate $WrapperSha $CliSha -NoWait }
        catch { $failures.Add("$role dispatch: $($_.Exception.Message)") }
    }
    foreach ($role in $sources.Keys) {
        if (!$runs.ContainsKey($role)) { continue }
        try { $null=Wait-MatlabRun $sources[$role].repository ([string]$runs[$role].id) $sources[$role].sha 'wss-preflight.yml' 'workflow_dispatch' }
        catch { $failures.Add("$role preflight: $($_.Exception.Message)") }
    }
    if ($failures.Count) { throw ('No native MATLAB approval: '+($failures -join '; ')) }
    [ordered]@{schema='wss-matlab-promotion/v1';candidate=$Candidate
        wrapper=@{source_sha=$WrapperSha;preflight_run_id=[string]$runs.wrapper.id}
        cli=@{source_sha=$CliSha;preflight_run_id=[string]$runs.cli.id}
        fixture=@{commit=$Config.fixture_commit;sha256=$Config.fixture_sha256}}
}
function Get-MatlabEvidence([string]$Repository,[string]$RunId,[string]$SourceSha,[string]$Role,$Candidate,[string]$Root,$Config) {
    $expectedRepository=if ($Role -ceq 'wrapper') { $MatlabWrapperRepository } else { (Get-MatlabApplication $Role).repository }
    if ($Repository -cne $expectedRepository) { throw 'Role/repository evidence mismatch.' }
    $run=Wait-MatlabRun $Repository $RunId $SourceSha 'wss-preflight.yml' 'workflow_dispatch'
    if ($run.head_branch -cne 'dev') { throw 'Preflight must execute trusted dev source.' }
    $pages=Invoke-MatlabGh @('api','--paginate','--slurp',"repos/$Repository/actions/runs/$RunId/jobs?per_page=100&filter=latest") | ConvertFrom-Json
    $prefix=if ($Role -ceq 'wrapper') { 'Preflight' } else { 'CLI preflight' }
    foreach ($name in @("$prefix behavioral tests","$prefix compatibility (Windows)","$prefix compatibility (Ubuntu)","$prefix compatibility (macOS)")) {
        $required=@($pages | ForEach-Object { $_.jobs } | Where-Object { $_.name -ceq $name })
        if ($required.Count -ne 1 -or $required[0].conclusion -cne 'success') { throw "Missing/skipped/failed native preflight job: $name" }
    }
    if (Test-Path -LiteralPath $Root) { throw 'Evidence destination must be new.' }
    $null=Invoke-MatlabGh @('run','download',$RunId,'--repo',$Repository,'--name','matlab-preflight-evidence','--dir',$Root)
    $actual=@(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') })
    if (@(Compare-Object @('evidence.json','summary.json','projection.json') $actual -CaseSensitive).Count) { throw 'Incomplete/extra native evidence files.' }
    $e=Get-Content (Join-Path $Root 'evidence.json') -Raw | ConvertFrom-Json
    Assert-MatlabSameCandidate $e.candidate $Candidate
    $own=if ($Role -ceq 'wrapper') { $e.wrapper_sha } else { $e.cli_sha }
    if ($e.schema -cne 'wss-matlab-evidence/v1' -or $e.execution -cne 'matlab-native' -or $e.role -cne $Role -or
        $e.run_repository -cne $Repository -or [string]$e.run_id -cne $RunId -or $e.run_sha -cne $SourceSha -or $own -cne $SourceSha -or
        $e.fixture_sha -cne $Config.fixture_commit -or $e.fixture_sha256 -cne $Config.fixture_sha256 -or $e.matlab_release -cne $Config.matlab_release) { throw 'Wrong native runtime/source/suite identity.' }
    if ((Get-FileHash (Join-Path $Root 'summary.json')).Hash.ToLowerInvariant() -cne $e.summary_sha256) { throw 'Native summary hash mismatch.' }
    $summary=Get-Content (Join-Path $Root 'summary.json') -Raw | ConvertFrom-Json
    $expectedTests=if ($Role -ceq 'wrapper') { 5 } else { 4 }
    if ($summary.testsPassed -ne $expectedTests -or $summary.scenariosPassed -ne 10 -or $summary.cases.Count -ne 10 -or
        @($summary.cases | Where-Object { $_.Passed -cne $true -or $_.Failure }).Count -or
        @(Compare-Object @($Config.expected_cases) @($summary.cases.Id) -CaseSensitive).Count) { throw 'Missing/duplicate/failed native canonical cases or tests.' }
    $projection=Get-Content (Join-Path $Root 'projection.json') -Raw | ConvertFrom-Json
    Assert-MatlabSameCandidate $projection.candidate $Candidate
    if ($projection.bootstrap_reference -cne $false -or $projection.schema -cne 'wss-matlab-projection/v1' -or
        $projection.files.Count -ne $MatlabProjectionFiles.Count -or @(Compare-Object $MatlabProjectionFiles @($projection.files.source) -CaseSensitive).Count -or
        (Get-MatlabProjectionDigest $projection.files) -cne $e.projection_sha256 -or $projection.projection_sha256 -cne $e.projection_sha256) { throw 'Projection/evidence mismatch.' }
    $e
}
