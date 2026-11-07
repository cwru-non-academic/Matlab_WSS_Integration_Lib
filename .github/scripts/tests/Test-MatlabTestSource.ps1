$ErrorActionPreference='Stop'
. "$PSScriptRoot/../MatlabTestSource.ps1"
$work=Join-Path ([IO.Path]::GetTempPath()) ('wss-matlab-binding-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
$script:passed=0
function Write-File([string]$Path,[string]$Text){$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path);[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function Commit-Fixture([string]$Root){$null=Invoke-MatlabTestGit $Root @('add','.');$null=Invoke-MatlabTestGit $Root @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','test fixture');((Invoke-MatlabTestGit $Root @('rev-parse','HEAD')) -join '').Trim()}
function Reject([scriptblock]$Action,[string]$Name){try{& $Action}catch{$script:passed++;Write-Output "PASS rejection: $Name";return};throw "Accepted invalid binding: $Name"}
$root=Join-Path $work 'tests'
$null=New-Item -ItemType Directory -Path $root
$null=Invoke-MatlabTestGit $root @('init','-q')
Write-File (Join-Path $root '.gitignore') '*.ignored'
Write-File (Join-Path $root 'tests/test-contract.json') '{"schema":"wss-matlab-tests/v1","role":"wrapper","test_directory":"tests","conformance_directory":"conformance"}'
Write-File (Join-Path $root 'tests/TestDistinct.m') 'function tests = TestDistinct; tests = functiontests(localfunctions); end'
foreach($name in @('runConformance','checkCompatibility')){Write-File (Join-Path $root "conformance/$name.m") "function value = $name(); value = []; end"}
$sha=Commit-Fixture $root
$product=Join-Path $work 'fixed-product'
$repo='cwru-non-academic/Matlab_WSS_Integration_Lib'
$id='a'*64
$bundle=Resolve-MatlabTestSource wrapper $product $root $sha $repo $id
Assert-MatlabTestSource $bundle $product
if($bundle.root -cne $root -or $bundle.sha -cne $sha -or $bundle.hashes.Count -ne 3){throw 'Distinct-source binding lost selected native sources.'}
$script:passed++;'PASS distinct selected source binding'
Reject {Resolve-MatlabTestSource wrapper $product $root $sha $repo ''} 'partial tuple'
Reject {Resolve-MatlabTestSource wrapper $product $root ('0'*40) $repo $id} 'wrong SHA'
Reject {Resolve-MatlabTestSource wrapper $root $root $sha $repo $id} 'product root used as test source'
Reject {Resolve-MatlabTestSource wrapper $product (Join-Path $root 'tests') $sha $repo $id} 'nested checkout root'
Reject {Resolve-MatlabTestSource wrapper $product $root $sha 'other/repository' $id} 'repository role mismatch'
Reject {Resolve-MatlabTestSource wrapper $product $root $sha $repo '../escape'} 'malformed selection ID'
Write-File (Join-Path $root 'tests/TestDistinct.m') 'mutated'
Reject {Assert-MatlabTestSource $bundle $product} 'tracked mutation'
$null=Invoke-MatlabTestGit $root @('restore','tests/TestDistinct.m')
Write-File (Join-Path $root 'tests/override.ignored') 'override'
Reject {Assert-MatlabTestSource $bundle $product} 'ignored override'
Remove-Item -LiteralPath (Join-Path $root 'tests/override.ignored')
Write-File (Join-Path $root 'tests/Extra.m') 'untracked'
Reject {Assert-MatlabTestSource $bundle $product} 'untracked override'
Remove-Item -LiteralPath (Join-Path $root 'tests/Extra.m')
$null=Invoke-MatlabTestGit $root @('update-index','--assume-unchanged','tests/TestDistinct.m')
Reject {Assert-MatlabTestSource $bundle $product} 'hidden index flags'
$null=Invoke-MatlabTestGit $root @('update-index','--no-assume-unchanged','tests/TestDistinct.m')
Write-File (Join-Path $root 'tests/test-contract.json') '{"schema":"wss-matlab-tests/v1","role":"wrapper","test_directory":"../src","conformance_directory":"conformance"}'
$badSha=Commit-Fixture $root
Reject {Resolve-MatlabTestSource wrapper $product $root $badSha $repo $id} 'committed path escape'
Write-File (Join-Path $root 'tests/test-contract.json') '{"schema":"wss-matlab-tests/v1","role":"cli","test_directory":"tests","conformance_directory":"conformance"}'
foreach($name in @('runCliConformance','checkCliCompatibility')){Write-File (Join-Path $root "conformance/$name.m") "function value = $name(); value = []; end"}
$cliSha=Commit-Fixture $root
$cli=Resolve-MatlabTestSource cli $product $root $cliSha 'cwru-non-academic/CLI_Matlab_WSS_Application' $id
Assert-MatlabTestSource $cli $product
$script:passed++;'PASS distinct CLI source binding'
$blob=((Invoke-MatlabTestGit $root @('hash-object','tests/TestDistinct.m')) -join '').Trim()
$null=Invoke-MatlabTestGit $root @('update-index','--add','--cacheinfo',"120000,$blob,tests/Linked.m")
$null=Invoke-MatlabTestGit $root @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','symbolic link fixture')
$linkSha=((Invoke-MatlabTestGit $root @('rev-parse','HEAD')) -join '').Trim()
$null=Invoke-MatlabTestGit $root @('checkout','--','tests/Linked.m')
Reject {Resolve-MatlabTestSource cli $product $root $linkSha 'cwru-non-academic/CLI_Matlab_WSS_Application' $id} 'tracked symbolic link'
Write-Output "PASS: $script:passed MATLAB binding checks. Fixture retained at $work"
