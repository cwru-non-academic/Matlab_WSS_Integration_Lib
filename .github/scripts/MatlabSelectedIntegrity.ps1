. "$PSScriptRoot/MatlabTestSource.ps1"
function Assert-MatlabToolsCheckout([string]$Root,[string]$Sha) {
    Assert-MatlabTestCheckout $Root $Sha
    $null=Assert-MatlabTestPath $Root '.github/scripts/Invoke-SelectedMatlabTests.ps1'
    $paths=@('.github/scripts','.github/matlab-ci.json')
    if(@(Invoke-MatlabTestGit $Root (@('status','--porcelain','--untracked-files=all','--ignored','--')+$paths)).Count){throw 'Executing MATLAB tools contain ignored or untracked overrides.'}
    foreach($entry in @(Invoke-MatlabTestGit $Root (@('ls-files','--stage','--')+$paths))){
        if($entry -cnotmatch '^100644 [a-f0-9]{40} 0\t(.+)$'){throw 'Executing MATLAB tools must be regular tracked files.'}
        $null=Assert-MatlabTestPath $Root $Matches[1]
    }
}
function Get-MatlabBaselineEvidence([string]$Root,[ValidateSet('behavioral','general')][string]$Purpose) {
    $directory=Assert-MatlabTestPath $Root 'artifacts/ci'
    $expected=@("$Purpose.json",'compatibility.json')
    if($Purpose -ceq 'general'){$expected+='matlab-root.txt'}
    $entries=@(Get-ChildItem -LiteralPath $directory -Force)
    if($entries.Count -ne $expected.Count -or @($entries|Where-Object PSIsContainer).Count -or
       @(Compare-Object $expected @($entries.Name) -CaseSensitive).Count){throw 'Required baseline evidence file inventory changed.'}
    @(foreach($name in ($expected|Sort-Object)){
        $relative="artifacts/ci/$name"
        $path=Assert-MatlabTestPath $Root $relative
        [pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
}
function Assert-MatlabBaselineEvidence([string]$Root,[string]$Purpose,$Snapshot) {
    $actual=Get-MatlabBaselineEvidence $Root $Purpose
    if(($actual|ConvertTo-Json -Compress) -cne ($Snapshot|ConvertTo-Json -Compress)){throw 'Selected suite modified mandatory baseline evidence.'}
}
function Get-MatlabToolsSource([string]$Root) {
    $paths=[Collections.Generic.List[string]]::new()
    $paths.Add('.github/matlab-ci.json');$paths.Add('.github/scripts')
    $null=Assert-MatlabTestPath $Root '.github/matlab-ci.json'
    $directories=[Collections.Generic.Stack[string]]::new()
    $directories.Push((Assert-MatlabTestPath $Root '.github/scripts'))
    while($directories.Count){
        foreach($entry in Get-ChildItem -LiteralPath $directories.Pop() -Force){
            $relative=[IO.Path]::GetRelativePath($Root,$entry.FullName).Replace('\','/')
            $null=Assert-MatlabTestPath $Root $relative
            $paths.Add($relative)
            if($entry.PSIsContainer){$directories.Push($entry.FullName)}
        }
    }
    $paths.Sort([StringComparer]::Ordinal)
    @(foreach($relative in $paths){
        $path=Assert-MatlabTestPath $Root $relative
        $item=Get-Item -LiteralPath $path -Force
        if($item.PSIsContainer){[pscustomobject]@{path=$relative;type='directory';sha256=''}}
        else{[pscustomobject]@{path=$relative;type='file';sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
    })
}
function Assert-MatlabToolsSource([string]$Root,$Snapshot) {
    $actual=Get-MatlabToolsSource $Root
    if(($actual|ConvertTo-Json -Compress) -cne ($Snapshot|ConvertTo-Json -Compress)){throw 'Selected suite modified executing MATLAB tools.'}
}