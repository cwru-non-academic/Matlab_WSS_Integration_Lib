# Trusted bootstrap: the frozen Core plan authenticates selection before this helper.
# This validates local source binding, never authorization from an ID alone.
Set-StrictMode -Version Latest
function Invoke-MatlabTestGit([string]$Root,[string[]]$Arguments) {
    $out=& git -C $Root @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $($out -join "`n")" }
    @($out)
}
function Assert-MatlabTestCheckout([string]$Root,[string]$Sha) {
    if ($Sha -cnotmatch '^[a-f0-9]{40}$') { throw 'Full immutable source SHA required.' }
    $full=[IO.Path]::GetFullPath($Root)
    $top=[IO.Path]::GetFullPath(((Invoke-MatlabTestGit $full @('rev-parse','--show-toplevel')) -join '').Trim())
    if ($full -ine $top -or ((Invoke-MatlabTestGit $full @('rev-parse','HEAD')) -join '').Trim() -cne $Sha) { throw 'Source root or SHA differs from the frozen checkout.' }
    if (@(Invoke-MatlabTestGit $full @('status','--porcelain','--untracked-files=all')).Count) { throw 'Source checkout must be clean.' }
    if (@(Invoke-MatlabTestGit $full @('ls-files','-v') | Where-Object { $_ -cmatch '^[a-zS] ' }).Count) { throw 'Hidden index changes are not allowed.' }
}
function Assert-MatlabTestPath([string]$Root,[string]$Relative) {
    $path=Join-Path $Root $Relative
    $cursor=Get-Item -LiteralPath $path -Force
    while ($null -ne $cursor) {
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked source paths are forbidden.' }
        $cursor=if($cursor -is [IO.FileInfo]){$cursor.Directory}else{$cursor.Parent}
    }
    $path
}
function Resolve-MatlabTestSource([string]$Role,[string]$ProductRoot,[string]$TestRoot,[string]$TestSha,[string]$TestRepository,[string]$TestSelectionId) {
    if (!$TestRoot -or !$TestSha -or !$TestRepository -or !$TestSelectionId) { throw 'TestRoot, TestSha, TestRepository and TestSelectionId must be supplied together.' }
    if ($Role -cnotin @('wrapper','cli') -or $TestSelectionId -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid role or frozen selection ID.' }
    $expected=if($Role -ceq 'wrapper'){'cwru-non-academic/Matlab_WSS_Integration_Lib'}else{'cwru-non-academic/CLI_Matlab_WSS_Application'}
    if ($TestRepository -cne $expected) { throw 'Test repository does not match the registered family role.' }
    $root=[IO.Path]::GetFullPath($TestRoot)
    if ($root -ieq [IO.Path]::GetFullPath($ProductRoot)) { throw 'Selected tests require a distinct checkout.' }
    Assert-MatlabTestCheckout $root $TestSha
    $contractPath=Assert-MatlabTestPath $root 'tests/test-contract.json'
    $contract=Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if (@(Compare-Object @('schema','role','test_directory','conformance_directory') @($contract.PSObject.Properties.Name) -CaseSensitive).Count -or $contract.schema -cne 'wss-matlab-tests/v1' -or $contract.role -cne $Role -or $contract.test_directory -cne 'tests' -or $contract.conformance_directory -cne 'conformance') { throw 'Invalid test-only contract; executable or product paths cannot be selected.' }
    $paths=@('tests','conformance')
    if (@(Invoke-MatlabTestGit $root (@('status','--porcelain','--untracked-files=all','--ignored','--')+$paths)).Count) { throw 'Ignored or untracked test overrides are forbidden.' }
    $tracked=@(Invoke-MatlabTestGit $root (@('ls-files','--stage','--')+$paths))
    if (@($tracked | Where-Object { $_ -cnotmatch '^100644 ' }).Count) { throw 'Test trees must contain regular tracked files only.' }
    $files=@(Get-ChildItem -LiteralPath (Join-Path $root 'tests'),(Join-Path $root 'conformance') -Recurse -File | Where-Object Extension -CEQ '.m' | Sort-Object FullName)
    if (!$files.Count -or !@($files | Where-Object { $_.Name -clike 'Test*.m' }).Count) { throw 'Selected native test suite is empty.' }
    $hashes=@(foreach($file in $files){$relative=[IO.Path]::GetRelativePath($root,$file.FullName); $null=Assert-MatlabTestPath $root $relative; @{path=$relative;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()}})
    $required=if($Role -ceq 'wrapper'){@('runConformance.m','checkCompatibility.m')}else{@('runCliConformance.m','checkCliCompatibility.m')}
    foreach($name in $required){if(!(Test-Path -LiteralPath (Join-Path $root "conformance/$name") -PathType Leaf)){throw "Missing selected conformance function: $name"}}
    [pscustomobject]@{root=$root;sha=$TestSha;repository=$TestRepository;selection_id=$TestSelectionId;contract_sha256=(Get-FileHash -LiteralPath $contractPath).Hash.ToLowerInvariant();role=$Role;hashes=$hashes}
}
function Assert-MatlabTestSource($Bundle,[string]$ProductRoot) {
    $again=Resolve-MatlabTestSource $Bundle.role $ProductRoot $Bundle.root $Bundle.sha $Bundle.repository $Bundle.selection_id
    if ($again.contract_sha256 -cne $Bundle.contract_sha256 -or ($again.hashes | ConvertTo-Json -Depth 4 -Compress) -cne ($Bundle.hashes | ConvertTo-Json -Depth 4 -Compress)) { throw 'Selected test bytes changed during execution.' }
}
