param([string] $Configuration = 'Release')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$dll = Join-Path $repo "osu.Game.Rulesets.MOsu\bin\$Configuration\net10.0\osu.Game.Rulesets.MOsu.dll"
if (!(Test-Path -LiteralPath $dll)) { throw 'Compilez le ruleset avant de preparer le paquet.' }
$package = Join-Path $PSScriptRoot 'package'
[IO.Directory]::CreateDirectory($package) | Out-Null
Copy-Item -LiteralPath $dll -Destination (Join-Path $package 'osu.Game.Rulesets.MOsu.dll') -Force
$validation = @{
    ControlsValidated = $false
    DllSha256 = (Get-FileHash -LiteralPath $dll).Hash
    CoreSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'MOsuOffline.Core.psm1')).Hash
    ClientCompatibilityValidated = $false
    Note = 'Livraison bloquee par defaut. Tests de transition, NUnit, visuels et pare-feu requis avant validation.'
}
[IO.File]::WriteAllText((Join-Path $package 'validation.json'), ($validation | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host 'Paquet prepare sans installation. Le verrou de validation reste actif.'
