# Synthetic result-envelope regressions only; not native or campaign evidence.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../MatlabSelectedResults.ps1"
$config=Read-MatlabConfig "$PSScriptRoot/../../matlab-ci.json"
$candidate=@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='1';artifact_id='2';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
$projection=@{candidate=$candidate;projection_sha256=('c'*64);files=@(@{source='WSS_Core_Interface.dll';sha256=('d'*64)})}
$summary=@{testsPassed=8;matlab='26.2 (R2026b)';profile=@{name='layered-v1';fixture_commit=$config.fixture_commit;fixture_sha256=$config.fixture_sha256;fixture_path=$config.fixture_path;candidate=$candidate;projection_sha256=('c'*64);core_sha256=('d'*64)};scenariosPassed=16;cases=@($config.expected_cases|ForEach-Object{@{Id=$_;Passed=$true;Failure=''}});multiScenariosPassed=16;multiCases=@((@($config.legacy_expected_cases)+@($config.multidevice_expected_cases))|ForEach-Object{@{Id=$_;Passed=$true;Failure=''}})}
$compatibility=@{Serial='passed';Ble='passed'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('matlab-completeness-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
foreach($role in 'wrapper','cli') {
    $expected=if ($role -ceq 'wrapper') {8} else {9}
    $contract=@{role=$role;ids=@(1..$expected|ForEach-Object{"TestFixture/test$_"});legacy=$true}
    $summary.testsPassed=$expected
    Assert-MatlabSelectedBaseline $summary $config $projection $compatibility $role $contract
    foreach($count in @(0,1,($expected-1),($expected+1))) {
        $summary.testsPassed=$count
        $output=Join-Path $temp "$role-$count-evidence.json"
        $rejected=$false
        try {
            Assert-MatlabSelectedBaseline $summary $config $projection $compatibility $role $contract
            [IO.File]::WriteAllText($output,'unexpected evidence')
        } catch {
            if($_.Exception.Message -cne 'Mandatory native evidence is incomplete.'){throw}
            $rejected=$true
        }
        if(!$rejected -or (Test-Path -LiteralPath $output)){throw "Incomplete $role baseline count $count produced evidence."}
    }
}
$runner=[IO.File]::ReadAllText("$PSScriptRoot/../Invoke-SelectedMatlabTests.ps1")
$guard=$runner.IndexOf('Assert-MatlabSelectedBaseline $mandatory')
$selected=$runner.IndexOf('$selected=Join-Path')
if($guard -lt 0 -or $selected -le $guard){throw 'Baseline guard must run before selected staging and final evidence.'}
'PASS wrapper8/CLI9 accepted; baseline0/1/wrong-role counts rejected before evidence or selected staging.'