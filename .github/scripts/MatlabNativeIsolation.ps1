# Only trusted launch code runs in this scope. MATLAB always executes out of process.
function Invoke-MatlabCredentialIsolated([scriptblock]$Launch) {
    $removed=@{}
    try {
        foreach($entry in Get-ChildItem Env:){
            if($entry.Name -match '(?i)TOKEN|SECRET|PASSWORD|PRIVATE_KEY|CREDENTIAL' -or
               $entry.Name -in @('GITHUB_OUTPUT','GITHUB_ENV','GITHUB_PATH','GITHUB_STATE')){
                $removed[$entry.Name]=$entry.Value
                Remove-Item -LiteralPath ('Env:'+$entry.Name)
            }
        }
        & $Launch
    } finally {
        foreach($name in $removed.Keys){[Environment]::SetEnvironmentVariable($name,$removed[$name],'Process')}
    }
}
