param([string] $OutputPath = (Join-Path $PSScriptRoot 'firewall-result.json'))
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'Test-FirewallIntegration.ps1'
$output = [IO.Path]::GetFullPath($OutputPath)
$command = "& '" + $script.Replace("'", "''") + "' -OutputPath '" + $output.Replace("'", "''") + "'"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
try {
    $process = Start-Process -FilePath $powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-EncodedCommand', $encoded) -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if (!(Test-Path -LiteralPath $output)) { throw 'Rapport absent : elevation refusee ou test interrompu. Validation impossible.' }
    $result = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    if (!$result.Validated -or $process.ExitCode -ne 0) { throw $result.Error }
    Write-Host 'PASS integration pare-feu Windows (sonde uniquement).'
} catch { Write-Error $_; exit 1 }
