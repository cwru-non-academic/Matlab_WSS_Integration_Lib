# Native unit inventory is owned by the exact product source, not its tooling checkout.
function Assert-MatlabNativeTestIds($Ids) {
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($Ids -isnot [array] -or @($Ids).Count -eq 0) { throw 'Native test inventory must be nonempty.' }
    foreach ($id in $Ids) {
        if ($id -isnot [string] -or $id -cnotmatch '^[A-Za-z][A-Za-z0-9_]+/[A-Za-z][A-Za-z0-9_]+$' -or !$seen.Add($id)) {
            throw 'Invalid or duplicate native test ID.'
        }
    }
}
function Get-MatlabNativeTestContract([ValidateSet('wrapper','cli')][string]$Role,[string]$SourceSha,[string]$SourceRoot) {
    Assert-MatlabSha $SourceSha
    $repository=if ($Role -ceq 'wrapper') { $MatlabWrapperRepository } else { $MatlabCliRepository }
    $runner=if ($Role -ceq 'wrapper') { 'ci/runWrapperCi.m' } else { 'ci/runCliCi.m' }
    $manifest='ci/native-test-contract.json'
    if ($SourceRoot) {
        # git show reads immutable objects, never an uncommitted working manifest.
        $null=Invoke-MatlabGit $SourceRoot @('cat-file','-e',"${SourceSha}^{commit}")
        $entries=@(Invoke-MatlabGit $SourceRoot @('ls-tree',$SourceSha,'--',$manifest))
        if ($entries.Count -gt 1) { throw 'Ambiguous native source contract.' }
        $hasManifest=$entries.Count -eq 1
        if ($hasManifest) {
            if ($entries[0] -cnotmatch '^(100644|100755) blob [a-f0-9]{40}\tci/native-test-contract\.json$') { throw 'Native source contract is not a regular blob.' }
            $record=(Invoke-MatlabGit $SourceRoot @('show',"${SourceSha}:$manifest")) -join "`n" | ConvertFrom-Json
        }
        else {
            $testsTree=(Invoke-MatlabGit $SourceRoot @('rev-parse',"${SourceSha}:tests")).Trim()
            $runnerBlob=(Invoke-MatlabGit $SourceRoot @('rev-parse',"${SourceSha}:$runner")).Trim()
        }
    } else {
        # GitHub authenticates immutable objects at the evidence's already-verified owner SHA.
        $tree=Invoke-MatlabGh -Arguments @('api',"repos/$repository/git/trees/${SourceSha}?recursive=1") | ConvertFrom-Json
        if ($tree.truncated) { throw 'Truncated native source tree.' }
        $entry=@($tree.tree | Where-Object { $_.path -ceq $manifest })
        if ($entry.Count -gt 1) { throw 'Ambiguous native source contract.' }
        $hasManifest=$entry.Count -eq 1
        if ($hasManifest) {
            if ($entry[0].type -cne 'blob' -or $entry[0].mode -cnotin @('100644','100755')) { throw 'Native source contract is not a blob.' }
            $blob=Invoke-MatlabGh -Arguments @('api',"repos/$repository/git/blobs/$($entry[0].sha)") | ConvertFrom-Json
            if ($blob.encoding -cne 'base64' -or $blob.sha -cne $entry[0].sha) { throw 'Native contract blob identity mismatch.' }
            $record=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($blob.content)) | ConvertFrom-Json
        } else {
            $tests=@($tree.tree | Where-Object { $_.path -ceq 'tests' -and $_.type -ceq 'tree' })
            $runners=@($tree.tree | Where-Object { $_.path -ceq $runner -and $_.type -ceq 'blob' })
            if ($tests.Count -ne 1 -or $runners.Count -ne 1) { throw 'Missing immutable native suite/runner.' }
            $testsTree=$tests[0].sha; $runnerBlob=$runners[0].sha
        }
    }
    if ($hasManifest) {
        if ($record.schema -isnot [string] -or $record.role -isnot [string] -or
            $record.schema -cne 'wss-matlab-native-tests/v1' -or $record.role -cne $Role -or
            @($record.PSObject.Properties.Name | Where-Object { $_ -cnotin @('schema','role','ids') }).Count) { throw 'Native test contract role/schema mismatch.' }
        Assert-MatlabNativeTestIds $record.ids
        return [pscustomobject]@{role=$Role;ids=@($record.ids);legacy=$false;source_sha=$SourceSha;repository=$repository}
    }
    # Frozen exceptions authenticate BOTH exact tests and the reviewed assertSuccess runner.
    # No fallback count is allowed for an unknown historical source.
    $catalog=Get-Content "$PSScriptRoot/matlab-legacy-native-tests.json" -Raw | ConvertFrom-Json
    if ($catalog.schema -cne 'wss-matlab-legacy-native-tests/v1') { throw 'Invalid historical native catalog.' }
    $matches=@($catalog.suites | Where-Object { $_.role -ceq $Role -and $_.tests_tree -ceq $testsTree -and $_.runner_blob -ceq $runnerBlob })
    if ($matches.Count -ne 1) { throw 'Unregistered historical native suite/runner; source migration required.' }
    Assert-MatlabNativeTestIds $matches[0].ids
    [pscustomobject]@{role=$Role;ids=@($matches[0].ids);legacy=$true;source_sha=$SourceSha;repository=$repository}
}
function Assert-MatlabNativeTests($Summary,$Contract) {
    Assert-MatlabNativeTestIds $Contract.ids
    $count=$Summary.testsPassed
    $numeric=$count -is [int] -or $count -is [long] -or $count -is [double] -or $count -is [decimal]
    if (!$numeric -or ![double]::IsFinite([double]$count) -or [math]::Truncate([double]$count) -ne [double]$count -or
        $count -ne @($Contract.ids).Count) { throw 'Mandatory native evidence is incomplete.' }
    $hasResults=if ($Summary -is [Collections.IDictionary]) { $Summary.Contains('nativeTests') } else { $null -ne $Summary.PSObject.Properties['nativeTests'] }
    if (!$hasResults) {
        if ($Contract.legacy -ceq $true) { return }
        throw 'Native source contract requires explicit test results.'
    }
    $results=$Summary.nativeTests
    Assert-MatlabNativeTestIds $results.ids
    if (@($results.ids).Count -ne @($Contract.ids).Count -or
        @(Compare-Object @($Contract.ids) @($results.ids) -CaseSensitive).Count -or
        @($results.passed).Count -ne @($Contract.ids).Count -or
        @($results.failed).Count -ne @($Contract.ids).Count -or
        @($results.incomplete).Count -ne @($Contract.ids).Count -or
        @($results.passed | Where-Object { $_ -isnot [bool] -or $_ -cne $true }).Count -or
        @($results.failed | Where-Object { $_ -isnot [bool] -or $_ -cne $false }).Count -or
        @($results.incomplete | Where-Object { $_ -isnot [bool] -or $_ -cne $false }).Count) { throw 'Native test IDs/results differ from exact source contract.' }
}
