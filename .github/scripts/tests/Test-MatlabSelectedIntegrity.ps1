# Local filesystem fixtures only; not native or campaign evidence.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../MatlabSelectedIntegrity.ps1"
$temp=Join-Path ([IO.Path]::GetTempPath()) ('matlab-retained-proof-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $temp|Out-Null
$null=git -C $temp init -q
$temp=[IO.Path]::GetFullPath((git -C $temp rev-parse --show-toplevel).Trim())
$product=Join-Path $temp 'product';$tools=Join-Path $temp 'distinct-tools'
New-Item -ItemType Directory -Path "$product/artifacts/ci","$tools/.github/scripts" -Force|Out-Null
function Reject-BeforeEvidence([scriptblock]$Action,[string]$Name) {
    $output=Join-Path $temp "$Name-evidence.json";$rejected=$false
    try{& $Action;[IO.File]::WriteAllText($output,'unexpected evidence')}catch{$rejected=$true}
    if(!$rejected -or (Test-Path -LiteralPath $output)){throw "Integrity failure $Name emitted evidence."}
}
foreach($name in 'behavioral.json','compatibility.json'){[IO.File]::WriteAllText("$product/artifacts/ci/$name",'baseline')}
$cli=Join-Path $temp 'cli'
New-Item -ItemType Directory -Path "$cli/artifacts/ci" -Force|Out-Null
foreach($name in 'general.json','compatibility.json','matlab-root.txt'){[IO.File]::WriteAllText("$cli/artifacts/ci/$name",'baseline')}
$cliSnapshot=Get-MatlabBaselineEvidence $cli general
Assert-MatlabBaselineEvidence $cli general $cliSnapshot
Remove-Item -LiteralPath "$cli/artifacts/ci/matlab-root.txt"
Reject-BeforeEvidence {Get-MatlabBaselineEvidence $cli general} 'missing-cli-root'
$caseProbe=Join-Path $temp 'case-probe'
New-Item -ItemType Directory -Path $caseProbe|Out-Null
[IO.File]::WriteAllText("$caseProbe/probe",'same')
[IO.File]::WriteAllText("$caseProbe/PROBE",'same')
if(@(Get-ChildItem -LiteralPath $caseProbe).Count -eq 2){
    [IO.File]::WriteAllText("$product/artifacts/ci/BEHAVIORAL.json",'baseline')
    Reject-BeforeEvidence {Get-MatlabBaselineEvidence $product behavioral} 'case-distinct-extra'
    Remove-Item -LiteralPath "$product/artifacts/ci/BEHAVIORAL.json"
    'PASS case-distinct duplicate baseline names rejected even with identical bytes.'
}
$snapshot=Get-MatlabBaselineEvidence $product behavioral
Assert-MatlabBaselineEvidence $product behavioral $snapshot
[IO.File]::WriteAllText("$product/artifacts/ci/behavioral.json",'mutated')
Reject-BeforeEvidence {Assert-MatlabBaselineEvidence $product behavioral $snapshot} 'mutated-summary'
[IO.File]::WriteAllText("$product/artifacts/ci/behavioral.json",'baseline')
Remove-Item -LiteralPath "$product/artifacts/ci/compatibility.json"
Reject-BeforeEvidence {Assert-MatlabBaselineEvidence $product behavioral $snapshot} 'missing-file'
[IO.File]::WriteAllText("$product/artifacts/ci/compatibility.json",'baseline')
[IO.File]::WriteAllText("$product/artifacts/ci/extra.json",'extra')
Reject-BeforeEvidence {Assert-MatlabBaselineEvidence $product behavioral $snapshot} 'extra-file'
Remove-Item -LiteralPath "$product/artifacts/ci/extra.json"
Assert-MatlabBaselineEvidence $product behavioral $snapshot
[IO.File]::WriteAllText("$tools/.github/scripts/Invoke-SelectedMatlabTests.ps1",'# trusted tool')
[IO.File]::WriteAllText("$tools/.github/matlab-ci.json",'{}')
$null=git -C $tools init -q
$null=git -C $tools add .
$null=git -C $tools -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
if($LASTEXITCODE -ne 0){throw 'Cannot initialize tools fixture'}
$sha=(git -C $tools rev-parse HEAD).Trim()
Assert-MatlabToolsCheckout $tools $sha
[IO.File]::WriteAllText("$tools/.github/scripts/Invoke-SelectedMatlabTests.ps1",'# changed tool')
Reject-BeforeEvidence {Assert-MatlabToolsCheckout $tools $sha} 'distinct-tools-mutation'
[IO.File]::WriteAllText("$tools/.github/scripts/Invoke-SelectedMatlabTests.ps1",'# trusted tool')
[IO.File]::WriteAllText("$tools/.git/info/exclude",'*.ignored')
[IO.File]::WriteAllText("$tools/.github/scripts/override.ignored",'override')
Reject-BeforeEvidence {Assert-MatlabToolsCheckout $tools $sha} 'ignored-tools-override'
Remove-Item -LiteralPath "$tools/.github/scripts/override.ignored"
Assert-MatlabToolsCheckout $tools $sha
$original=[IO.Path]::GetFullPath("$product/artifacts/ci")
$moved=[IO.Path]::GetFullPath("$product/artifacts/original-ci")
if(!$original.StartsWith($temp+[IO.Path]::DirectorySeparatorChar) -or !$moved.StartsWith($temp+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe fixture move'}
Move-Item -LiteralPath $original -Destination $moved
$type=if($IsWindows){'Junction'}else{'SymbolicLink'}
New-Item -ItemType $type -Path $original -Target $moved|Out-Null
Reject-BeforeEvidence {Get-MatlabBaselineEvidence $product behavioral} 'redirected-baseline'
$runner=[IO.File]::ReadAllText("$PSScriptRoot/../Invoke-SelectedMatlabTests.ps1")
if($runner.IndexOf('$baselineEvidence=Get-MatlabBaselineEvidence') -ge $runner.IndexOf('$selected=Join-Path') -or
   $runner.IndexOf('Assert-MatlabBaselineEvidence $stagedProduct') -ge $runner.IndexOf('$evidence=[ordered]') -or
   ([regex]::Matches($runner,'Assert-MatlabToolsCheckout \$ToolsRoot \$ToolsSha')).Count -ne 2){throw 'Required parent integrity gate ordering changed.'}
'PASS baseline mutation/missing/extra/redirect and distinct-tools tracked/ignored mutations rejected before evidence; originals pass.'