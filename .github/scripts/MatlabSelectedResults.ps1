. "$PSScriptRoot/MatlabContract.ps1"
function Assert-MatlabSelectedBaseline($Summary,$Config,$Projection,$Compatibility,[ValidateSet('wrapper','cli')][string]$Role,$NativeContract) {
Assert-MatlabNativeSummary $Summary $Config $Projection -RequireModern
if ($NativeContract.role -cne $Role) { throw 'Native contract role mismatch.' }
Assert-MatlabNativeTests $Summary $NativeContract
if($Summary.scenariosPassed -ne $Config.expected_cases.Count -or
    @(Compare-Object @($Config.expected_cases) @($Summary.cases.Id) -CaseSensitive).Count -or
    @($Summary.cases | Where-Object { !$_.Passed -or $_.Failure }).Count -or
    $Summary.matlab -cnotmatch '\(R2026b\)' -or $Compatibility.Serial -cne 'passed' -or
    $Compatibility.Ble -cnotin @('passed','unsupported-by-legacy-payload','unsupported-by-Core')) { throw 'Mandatory native evidence is incomplete.' }
}
