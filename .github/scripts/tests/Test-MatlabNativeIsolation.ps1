. "$PSScriptRoot/../MatlabNativeIsolation.ps1"
$names=@('GH_TOKEN','GITHUB_TOKEN','WSS_TEST_VARIABLE_READ_TOKEN','DUMMY_SECRET','DUMMY_PASSWORD','DUMMY_PRIVATE_KEY','DUMMY_CREDENTIAL','GITHUB_OUTPUT','GITHUB_ENV','GITHUB_PATH','GITHUB_STATE')
$previous=@{}
try {
    foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,'dummy-not-a-credential')}
    Invoke-MatlabCredentialIsolated {
        $output=& pwsh -NoProfile -Command 'Get-ChildItem Env: | Where-Object { $_.Name -match "TOKEN|SECRET|PASSWORD|PRIVATE_KEY|CREDENTIAL" -or $_.Name -in @("GITHUB_OUTPUT","GITHUB_ENV","GITHUB_PATH","GITHUB_STATE") } | Select-Object -ExpandProperty Name'
        if($LASTEXITCODE -ne 0 -or $output){throw ('Child inherited credentials/runner handles: '+($output -join ',')+' exit '+$LASTEXITCODE)}
    }
    $failed=$false
    try {Invoke-MatlabCredentialIsolated {throw 'intentional child launch failure'}}catch{$failed=$true}
    if(!$failed){throw 'Missing intentional failure'}
    foreach($name in $names){if([Environment]::GetEnvironmentVariable($name) -cne 'dummy-not-a-credential'){throw "Parent environment not restored: $name"}}
    'PASS child credentials absent; parent restored after success and failure.'
} finally {foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name])}}
