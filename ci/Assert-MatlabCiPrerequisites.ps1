param([Parameter(Mandatory)][ValidateSet('Windows','Ubuntu','macOS')][string]$Platform)
$ErrorActionPreference = 'Stop'

# MathWorks public-project and batch-token licensing exclude external language
# interfaces, including .NET. Do not produce a synthetic pass on hosted runners.
if ($env:RUNNER_ENVIRONMENT -ne 'self-hosted') {
    $variable = 'WSS_MATLAB_' + $Platform.ToUpperInvariant() + '_RUNNER'
    throw "MATLAB/.NET CI requires a separately licensed self-hosted $Platform runner. No runner is configured. Set the $variable repository variable to JSON labels for an existing licensed runner. Public-project/batch-token licensing does not support .NET: https://github.com/matlab-actions/setup-matlab#notes"
}
if ($env:MLM_LICENSE_TOKEN) {
    throw 'Batch-token licensing does not support the external .NET interface. Provision a separately licensed MATLAB runner; do not replace production MATLAB tests with managed-only checks.'
}
$actual = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Ubuntu' } elseif ($IsMacOS) { 'macOS' } else { 'unsupported' }
if ($actual -cne $Platform) { throw "Expected $Platform; runner platform is $actual." }
if (-not (Get-Command matlab -ErrorAction SilentlyContinue)) { throw 'MATLAB R2026b must already be installed, separately licensed, and on PATH.' }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'An installed .NET SDK and .NET 8 runtime are required.' }
$runtimes = & dotnet --list-runtimes
if ($LASTEXITCODE -ne 0 -or -not ($runtimes -match '^Microsoft.NETCore.App 8\.')) { throw 'The separately licensed runner must provide the .NET 8 runtime.' }
$sdks = & dotnet --list-sdks
if ($LASTEXITCODE -ne 0 -or -not $sdks) { throw 'An installed .NET SDK is required to build the MATLAB managed host.' }
Write-Output "Prerequisites present for $Platform. Actual MATLAB/.NET execution below must still prove license and runtime compatibility."
