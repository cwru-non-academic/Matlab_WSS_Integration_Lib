# Synthetic contract regressions, not native evidence.
. "$PSScriptRoot/../MatlabContract.ps1"
function Reject([scriptblock]$Action){try{& $Action}catch{return};throw 'Expected rejection.'}
$config=Read-MatlabConfig "$PSScriptRoot/../../matlab-ci.json"
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot))
foreach($pair in @(@($config.fixture_path,$config.fixture_sha256),@($config.legacy_fixture_path,$config.legacy_fixture_sha256))){
    if((Get-MatlabFixtureHash (Join-Path $root $pair[0])) -cne $pair[1]){throw 'Fixture pin mismatch'}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('matlab-eol-'+[guid]::NewGuid()+'.m')
try {
    $text=[IO.File]::ReadAllText((Join-Path $root $config.fixture_path)).Replace("`r`n","`n")
    foreach($variant in @($text,$text.Replace("`n","`r`n"))){
        [IO.File]::WriteAllText($temp,$variant)
        if((Get-MatlabFixtureHash $temp) -cne $config.fixture_sha256){throw 'EOL-dependent pin.'}
    }
    [IO.File]::WriteAllText($temp,$text+'changed')
    if((Get-MatlabFixtureHash $temp) -ceq $config.fixture_sha256){throw 'Changed source accepted.'}
}finally{Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue}
$candidate=@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='1';artifact_id='2';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
$projection=@{candidate=$candidate;projection_sha256=('c'*64);files=@(@{source='WSS_Core_Interface.dll';sha256=('d'*64)})}
$summary=@{profile=@{name='legacy-v1';candidate=$candidate;projection_sha256=('c'*64);core_sha256=('d'*64)};scenariosPassed=10;cases=@($config.legacy_expected_cases|ForEach-Object{@{Id=$_;Passed=$true;Failure=''}});multiCases=@();multiScenariosPassed=0}
Assert-MatlabNativeSummary $summary $config $projection
Reject {Assert-MatlabNativeSummary $summary $config $projection -RequireModern}
$summary.profile.name='layered-v1';$summary.scenariosPassed=16;$summary.cases=@($config.expected_cases|ForEach-Object{@{Id=$_;Passed=$true;Failure=''}})
$summary.multiScenariosPassed=16;$summary.multiCases=@((@($config.legacy_expected_cases)+@($config.multidevice_expected_cases))|ForEach-Object{@{Id=$_;Passed=$true;Failure=''}})
Assert-MatlabNativeSummary $summary $config $projection -RequireModern
$summary.multiCases[0].Id='duplicate';Reject {Assert-MatlabNativeSummary $summary $config $projection}
$summary.profile.core_sha256='wrong';Reject {Assert-MatlabNativeSummary $summary $config $projection}
'PASS exact LF/CRLF pins, legacy compatibility, mandatory modern selection, multi inventory and DLL binding.'
