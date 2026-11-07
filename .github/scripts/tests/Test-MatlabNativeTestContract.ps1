# Synthetic immutable-object API responses; no native/live acceptance evidence.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../MatlabContract.ps1"
function Reject-NativeContract([scriptblock]$Action) {
    $rejected=$false; try { & $Action } catch { $rejected=$true }
    if (!$rejected) { throw 'Expected native source contract rejection.' }
}
$catalog=Get-Content "$PSScriptRoot/../matlab-legacy-native-tests.json" -Raw | ConvertFrom-Json
$global:NativeContractFixture=@{}
function Invoke-MatlabGh([string[]]$Arguments) {
    $f=$global:NativeContractFixture
    if ($Arguments[0] -cne 'api' -or $Arguments.Count -ne 2) { throw 'Unexpected fixture request.' }
    if ($Arguments[1] -ceq "repos/$($f.repository)/git/trees/$($f.sha)?recursive=1") { return ($f.tree | ConvertTo-Json -Depth 8) }
    if ($f.ContainsKey('blob') -and $Arguments[1] -ceq "repos/$($f.repository)/git/blobs/$($f.blob.sha)") { return ($f.blob | ConvertTo-Json -Depth 8) }
    throw 'Verifier requested something other than the exact immutable owner source.'
}
try {
    foreach ($old in $catalog.suites) {
        $repository=if ($old.role -ceq 'wrapper') {$MatlabWrapperRepository} else {$MatlabCliRepository}
        $runner=if ($old.role -ceq 'wrapper') {'ci/runWrapperCi.m'} else {'ci/runCliCi.m'}
        $global:NativeContractFixture=@{repository=$repository;sha=$old.reference_source;tree=@{truncated=$false;tree=@(@{path='tests';type='tree';sha=$old.tests_tree},@{path=$runner;type='blob';sha=$old.runner_blob})}}
        $contract=Get-MatlabNativeTestContract $old.role $old.reference_source
        Assert-MatlabNativeTests @{testsPassed=$old.ids.Count} $contract
        foreach ($json in @('{"testsPassed":[0]}','{"testsPassed":[8,8]}','{"testsPassed":[0,8]}','{"testsPassed":true}','{"testsPassed":"8"}','{"testsPassed":{}}','{"testsPassed":null}','{"testsPassed":8.5}')) {
            $malformed=$json | ConvertFrom-Json
            Reject-NativeContract { Assert-MatlabNativeTests $malformed $contract }
        }
        foreach ($count in @(0,1,($old.ids.Count-1),($old.ids.Count+1))) { Reject-NativeContract { Assert-MatlabNativeTests @{testsPassed=$count} $contract } }
        $global:NativeContractFixture.tree.tree[1].sha='a'*40
        Reject-NativeContract { Get-MatlabNativeTestContract $old.role $old.reference_source }
        $global:NativeContractFixture.tree.tree[1].sha=$old.runner_blob
        $global:NativeContractFixture.tree.tree[0].sha='b'*40
        Reject-NativeContract { Get-MatlabNativeTestContract $old.role $old.reference_source }
    }
    $ids=@('TestFixture/testOne','TestFixture/testTwo')
    $manifest=@{schema='wss-matlab-native-tests/v1';role='wrapper';ids=$ids}
    function Set-ManifestFixture($Manifest) {
        $global:NativeContractFixture=@{repository=$MatlabWrapperRepository;sha=('c'*40);tree=@{truncated=$false;tree=@(@{path='ci/native-test-contract.json';type='blob';mode='100644';sha=('d'*40)})};blob=@{sha=('d'*40);encoding='base64';content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Manifest|ConvertTo-Json -Depth 4)))}}
    }
    Set-ManifestFixture $manifest
    $contract=Get-MatlabNativeTestContract wrapper ('c'*40)
    $summary=@{testsPassed=2;nativeTests=@{ids=$ids;passed=@($true,$true);failed=@($false,$false);incomplete=@($false,$false)}}
    Assert-MatlabNativeTests $summary $contract
    foreach ($json in @('[0]','[2,2]','[0,2]','true','"2"','{}','null','2.5')) {
        $summary.testsPassed=$json | ConvertFrom-Json
        Reject-NativeContract { Assert-MatlabNativeTests $summary $contract }
    }
    $summary.testsPassed=2
    Reject-NativeContract { Assert-MatlabNativeTests @{testsPassed=2} $contract }
    foreach ($field in @('passed','failed','incomplete')) {
        $prior=$summary.nativeTests[$field].Clone()
        $summary.nativeTests[$field][0]=!$summary.nativeTests[$field][0]
        Reject-NativeContract { Assert-MatlabNativeTests $summary $contract }
        $summary.nativeTests[$field]=$prior
    }
    foreach ($wrong in @(@('TestFixture/testOne','TestFixture/testOne'),@('TestFixture/testOne'),@('TestFixture/testOne','TestFixture/testOther'),@('TestFixture/testOne','TestFixture/testTwo','TestFixture/testExtra'))) {
        $summary.nativeTests.ids=$wrong
        Reject-NativeContract { Assert-MatlabNativeTests $summary $contract }
    }
    $manifest.ids=@('TestFixture/testOne','TestFixture/testOne');Set-ManifestFixture $manifest
    Reject-NativeContract { Get-MatlabNativeTestContract wrapper ('c'*40) }
    $manifest.ids=$ids;$manifest.role='cli';Set-ManifestFixture $manifest
    Reject-NativeContract { Get-MatlabNativeTestContract wrapper ('c'*40) }
    $manifest.role='wrapper';Set-ManifestFixture $manifest
    $global:NativeContractFixture.tree.truncated=$true
    Reject-NativeContract { Get-MatlabNativeTestContract wrapper ('c'*40) }
    Set-ManifestFixture $manifest;$global:NativeContractFixture.blob.sha='e'*40
    Reject-NativeContract { Get-MatlabNativeTestContract wrapper ('c'*40) }
    Set-ManifestFixture $manifest
    Reject-NativeContract { Get-MatlabNativeTestContract wrapper ('f'*40) }
    foreach ($badManifest in @(
        @{schema=@('wss-matlab-native-tests/v1');role='wrapper';ids=$ids},
        @{schema='wss-matlab-native-tests/v1';role=@('wrapper');ids=$ids},
        @{schema='wss-matlab-native-tests/v1';role='wrapper';ids='TestFixture/testOne'})) {
        Set-ManifestFixture $badManifest
        Reject-NativeContract { Get-MatlabNativeTestContract wrapper ('c'*40) }
    }
    foreach ($shape in @(@{type='tree';mode='040000'},@{type='blob';mode='120000'},@{type='commit';mode='160000'})) {
        Set-ManifestFixture $manifest
        $global:NativeContractFixture.tree.tree[0].type=$shape.type
        $global:NativeContractFixture.tree.tree[0].mode=$shape.mode
        Reject-NativeContract { Get-MatlabNativeTestContract wrapper ('c'*40) }
    }
    # Exact local ls-tree path lookup must see directories/symlinks/gitlinks, not fall back.
    $global:NativeLocalFixture=$catalog.suites[0]
    $global:NativeLocalEntry=$null
    function Invoke-MatlabGit([string]$Root,[string[]]$Arguments) {
        if ($Root -cne 'synthetic-immutable-root') { throw 'Unexpected local fixture root.' }
        switch ($Arguments[0]) {
            'cat-file' { return }
            'ls-tree' {
                if ($Arguments.Count -ne 4 -or $Arguments[1] -cne $global:NativeLocalFixture.reference_source -or $Arguments[2] -cne '--' -or $Arguments[3] -cne 'ci/native-test-contract.json') { throw 'Wrong exact manifest-path lookup.' }
                if ($global:NativeLocalEntry) { return $global:NativeLocalEntry }
                return
            }
            'rev-parse' {
                if ($Arguments[1].EndsWith(':tests')) { return $global:NativeLocalFixture.tests_tree }
                if ($Arguments[1].EndsWith(':ci/runWrapperCi.m')) { return $global:NativeLocalFixture.runner_blob }
                throw 'Unexpected source lookup.'
            }
            default { throw 'Unexpected local Git operation.' }
        }
    }
    $local=Get-MatlabNativeTestContract wrapper $global:NativeLocalFixture.reference_source 'synthetic-immutable-root'
    if (!$local.legacy) { throw 'Absent historical manifest must retain its authenticated compatibility path.' }
    foreach ($kind in @('040000 tree','120000 blob','160000 commit')) {
        $global:NativeLocalEntry="$kind $('d'*40)`tci/native-test-contract.json"
        Reject-NativeContract { Get-MatlabNativeTestContract wrapper $global:NativeLocalFixture.reference_source 'synthetic-immutable-root' }
    }
    Write-Output 'PASS authenticated historical suite+runner, immutable owner manifest, exact IDs, duplicates, skips, extras and forged counts rejected.'
} finally { Remove-Variable NativeContractFixture -Scope Global; Remove-Variable NativeLocalFixture,NativeLocalEntry -Scope Global -ErrorAction SilentlyContinue }
