[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('wrapper','cli')][string]$Role,
    [Parameter(Mandatory)][string]$ProductRoot,
    [Parameter(Mandatory)][string]$ProductSha,
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$TestRoot,
    [Parameter(Mandatory)][string]$TestSha,
    [Parameter(Mandatory)][string]$TestRepository,
    [Parameter(Mandatory)][string]$TestSelectionId,
    [string]$WrapperRoot='', [string]$WrapperSha='', [string]$MatlabExecutable='matlab'
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/MatlabTestSource.ps1"
. "$PSScriptRoot/MatlabContract.ps1"
. "$PSScriptRoot/MatlabNativeIsolation.ps1"
. "$PSScriptRoot/MatlabSelectedResults.ps1"
. "$PSScriptRoot/MatlabSelectedIntegrity.ps1"
$ToolsRoot=Split-Path (Split-Path $PSScriptRoot)
$ToolsSha=((Invoke-MatlabTestGit $ToolsRoot @('rev-parse','HEAD')) -join '').Trim()
Assert-MatlabToolsCheckout $ToolsRoot $ToolsSha
$toolsSource=Get-MatlabToolsSource $ToolsRoot
$ProductRoot=[IO.Path]::GetFullPath($ProductRoot)
$PayloadRoot=[IO.Path]::GetFullPath($PayloadRoot)
$WorkRoot=[IO.Path]::GetFullPath($WorkRoot)
Assert-MatlabTestCheckout $ProductRoot $ProductSha
if($Role -ceq 'wrapper'){$WrapperRoot=$ProductRoot;$WrapperSha=$ProductSha}
elseif(!$WrapperRoot -or !$WrapperSha){throw 'CLI requires explicit unchanged wrapper product root and SHA.'}
$WrapperRoot=[IO.Path]::GetFullPath($WrapperRoot)
Assert-MatlabTestCheckout $WrapperRoot $WrapperSha
$bundle=Resolve-MatlabTestSource $Role $ProductRoot $TestRoot $TestSha $TestRepository $TestSelectionId
foreach($root in @($ProductRoot,$WrapperRoot,$bundle.root,$PayloadRoot)){
    if($WorkRoot -ieq $root -or $WorkRoot.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'WorkRoot must be outside original source and payload roots.'}
}
# Product baseline and candidate projection are mandatory, never selected config.
$config=Read-MatlabConfig (Join-Path $WrapperRoot '.github/matlab-ci.json')
$suite=[IO.File]::ReadAllText((Join-Path $WrapperRoot $config.fixture_path)).Replace("`r`n","`n")
$suiteHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($suite))).ToLowerInvariant()
if($config.baseline_ready -cne $true){throw 'Product native baseline approval is missing.'}
if($suiteHash -cne $config.fixture_sha256){throw 'Mandatory product canonical fixture differs from its reviewed pin.'}
$projection=Get-Content -LiteralPath (Join-Path $PayloadRoot 'payload-source.json') -Raw | ConvertFrom-Json
Assert-MatlabProjection $PayloadRoot $projection
if(Test-Path -LiteralPath $WorkRoot){throw 'Selected validation WorkRoot must be new.'}
$null=New-Item -ItemType Directory -Path $WorkRoot
function Export-Product([string]$Root,[string]$Sha,[string]$Destination,[string]$Name){
    $zip=Join-Path $WorkRoot "$Name.zip"
    $null=Invoke-MatlabTestGit $Root @('archive','--format=zip',"--output=$zip",$Sha)
    Expand-Archive -LiteralPath $zip -DestinationPath $Destination
}
$stagedWrapper=Join-Path $WorkRoot 'wrapper'
Export-Product $WrapperRoot $WrapperSha $stagedWrapper 'wrapper'
$stagedProduct=$stagedWrapper
if($Role -ceq 'cli'){
    $stagedProduct=Join-Path $WorkRoot 'cli'
    Export-Product $ProductRoot $ProductSha $stagedProduct 'cli'
}
# Only this new disposable mirror receives the exact validated payload.
$stagedPayload=Join-Path $stagedWrapper 'Cs_Libraries'
foreach($file in Get-ChildItem -LiteralPath $stagedPayload -Recurse -File){Remove-Item -LiteralPath $file.FullName}
Copy-Item -Path (Join-Path $PayloadRoot '*') -Destination $stagedPayload -Recurse -Force
Assert-MatlabProjection $stagedPayload $projection
& dotnet build (Join-Path $stagedWrapper 'managed/Wss.Matlab.Managed.csproj') -c Release
if($LASTEXITCODE -ne 0){throw 'Mandatory product managed host build failed.'}
& dotnet run --project (Join-Path $stagedWrapper 'tests/managed/ManagedHostChecks.csproj') -c Release
if($LASTEXITCODE -ne 0){throw 'Mandatory product managed lifecycle checks failed.'}
if($Role -ceq 'cli'){
    $link=Join-Path $stagedProduct 'external/wss-matlab-wrapper'
    $null=New-Item -ItemType Directory -Force -Path $link
    Copy-Item -Path (Join-Path $stagedWrapper '*') -Destination $link -Recurse -Force
    $stagedWrapper=$link
    $stagedPayload=Join-Path $stagedWrapper 'Cs_Libraries'
}
function Invoke-SelectedMatlabNative([string]$Expression,[string]$Name){
    Invoke-MatlabCredentialIsolated {
    if($IsWindows){
        $executable=(Get-Command $MatlabExecutable -ErrorAction Stop).Source
        $direct=Join-Path (Split-Path -Parent $executable) 'win64/MATLAB.exe'
        if(Test-Path -LiteralPath $direct){$executable=$direct}
        if($Expression.Contains('"')){throw 'Unexpected double quote in native MATLAB expression.'}
        $out=Join-Path $WorkRoot "$Name.stdout.log"
        $err=Join-Path $WorkRoot "$Name.stderr.log"
        $process=Start-Process -FilePath $executable -ArgumentList @('-batch',('"'+$Expression+'"')) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
        Get-Content -LiteralPath $out | Write-Host
        Get-Content -LiteralPath $err | Write-Host
        if($process.ExitCode -ne 0){throw "Native MATLAB $Name failed: $($process.ExitCode)"}
    }else{
        & $MatlabExecutable -batch $Expression
        if($LASTEXITCODE -ne 0){throw "Native MATLAB $Name failed."}
    }
}
}
function Quote-Matlab([string]$Value){"'"+$Value.Replace("'","''")+"'"}
$entry=if($Role -ceq 'wrapper'){'runWrapperCi'}else{'runCliCi'}
$purpose=if($Role -ceq 'wrapper'){'behavioral'}else{'general'}
$baseline="restoredefaultpath; addpath($(Quote-Matlab (Join-Path $stagedProduct 'ci'))); $entry('$purpose'); $entry('compatibility');"
Invoke-SelectedMatlabNative $baseline 'mandatory'
$mandatory=Get-Content -LiteralPath (Join-Path $stagedProduct "artifacts/ci/$purpose.json") -Raw | ConvertFrom-Json
$compatibility=Get-Content -LiteralPath (Join-Path $stagedProduct 'artifacts/ci/compatibility.json') -Raw | ConvertFrom-Json
$nativeContract=Get-MatlabNativeTestContract $Role $ProductSha $ProductRoot
Assert-MatlabSelectedBaseline $mandatory $config $projection $compatibility $Role $nativeContract
$baselineEvidence=Get-MatlabBaselineEvidence $stagedProduct $purpose
$selected=Join-Path $WorkRoot 'selected' 
foreach($file in $bundle.hashes){
    $destination=Join-Path $selected $file.path
    $null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
    Copy-Item -LiteralPath (Join-Path $bundle.root $file.path) -Destination $destination
    if((Get-FileHash -LiteralPath $destination).Hash.ToLowerInvariant() -cne $file.sha256){throw 'Selected source copy changed.'}
}
# Freeze source bytes in disposable products too; selected tests cannot mutate code.
function Get-StagedMatlabSource([string]$Root){
    @(foreach($part in @('src','Config','ci','conformance','managed')){
        if(Test-Path -LiteralPath (Join-Path $Root $part)){
            Get-ChildItem -LiteralPath (Join-Path $Root $part) -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
        }
    }) -join "`n"
}
$productBytes=Get-StagedMatlabSource $stagedProduct
$wrapperBytes=Get-StagedMatlabSource $stagedWrapper
$settings=@{WSS_SELECTED_ROLE=$Role;WSS_SELECTED_PRODUCT=$stagedProduct;WSS_SELECTED_WRAPPER=$stagedWrapper;WSS_SELECTED_TESTS=$selected;WSS_SELECTED_OUTPUT=$WorkRoot}
$previous=@{}
try{
    foreach($key in $settings.Keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key);[Environment]::SetEnvironmentVariable($key,$settings[$key])}
    Invoke-SelectedMatlabNative "addpath($(Quote-Matlab $PSScriptRoot)); runSelectedMatlabTests;" 'selected'
} finally {foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key])}}
if((Get-StagedMatlabSource $stagedProduct) -cne $productBytes -or (Get-StagedMatlabSource $stagedWrapper) -cne $wrapperBytes){throw 'Selected suite modified staged product source.'}
foreach($file in $bundle.hashes){if((Get-FileHash -LiteralPath (Join-Path $selected $file.path)).Hash.ToLowerInvariant() -cne $file.sha256){throw 'Selected staged test bytes changed during execution.'}}
Assert-MatlabTestSource $bundle $ProductRoot
Assert-MatlabTestCheckout $ProductRoot $ProductSha
Assert-MatlabTestCheckout $WrapperRoot $WrapperSha
Assert-MatlabProjection $PayloadRoot $projection
Assert-MatlabProjection $stagedPayload $projection
Assert-MatlabToolsCheckout $ToolsRoot $ToolsSha
Assert-MatlabToolsSource $ToolsRoot $toolsSource
Assert-MatlabBaselineEvidence $stagedProduct $purpose $baselineEvidence
$summary=Get-Content -LiteralPath (Join-Path $WorkRoot 'selected-summary.json') -Raw | ConvertFrom-Json
if($summary.testsPassed -lt 1 -or $summary.matlab -cnotmatch '\(R2026b\)'){throw 'Selected native summary missing real test execution.'}
$evidence=[ordered]@{schema='wss-selected-matlab-tests/v1';role=$Role;tools_root=$ToolsRoot;tools_sha=$ToolsSha;tools_source_hashes=$toolsSource;baseline_evidence=$baselineEvidence;product_root=$ProductRoot;product_sha=$ProductSha;wrapper_root=$WrapperRoot;wrapper_sha=$WrapperSha;payload_root=$PayloadRoot;projection_sha256=$projection.projection_sha256;fixture_sha256=$suiteHash;test_root=$bundle.root;test_sha=$bundle.sha;test_repository=$bundle.repository;test_selection_id=$bundle.selection_id;test_contract_sha256=$bundle.contract_sha256;mandatory_product_gates='passed';profile=$mandatory.profile;selected_suite='passed';physical_transport='not-executed';summary_sha256=(Get-FileHash -LiteralPath (Join-Path $WorkRoot 'selected-summary.json')).Hash.ToLowerInvariant()}
$evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test-source-evidence.json')
$evidence
