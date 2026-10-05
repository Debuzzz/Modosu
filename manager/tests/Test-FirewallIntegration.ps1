param([string] $OutputPath = (Join-Path $PSScriptRoot 'firewall-result.json'))
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\MOsuOffline.Core.psm1') -Force
$probeBuild = Join-Path $PSScriptRoot 'FirewallProbe\bin\Release\net10.0'
if (!(Test-Path -LiteralPath (Join-Path $probeBuild 'FirewallProbe.exe'))) { throw 'Compilez FirewallProbe en Release avant le test.' }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('MOsuOffline-firewall-' + [Guid]::NewGuid().ToString('N'))
$gameDir = Join-Path $fixture 'lazer\current'
[IO.Directory]::CreateDirectory($gameDir) | Out-Null
Get-ChildItem -LiteralPath $probeBuild -File | Copy-Item -Destination $gameDir
Rename-Item -LiteralPath (Join-Path $gameDir 'FirewallProbe.exe') -NewName 'osu!.exe'
$packageDir = Join-Path $fixture 'package'
[IO.Directory]::CreateDirectory($packageDir) | Out-Null
$dll = Join-Path $packageDir 'osu.Game.Rulesets.MOsu.dll'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\..\osu.Game.Rulesets.MOsu\bin\Release\net10.0\osu.Game.Rulesets.MOsu.dll') -Destination $dll
$core = Join-Path $PSScriptRoot '..\MOsuOffline.Core.psm1'
$receipt = @{ ControlsValidated = $true; DllSha256 = (Get-FileHash $dll).Hash; CoreSha256 = (Get-FileHash $core).Hash }
[IO.File]::WriteAllText((Join-Path $packageDir 'validation.json'), ($receipt | ConvertTo-Json))
$ctx = New-OfflineContext (Join-Path $fixture 'lazer') (Join-Path $fixture 'data') $dll (Join-Path $fixture 'vault')
function Invoke-TestHelper([string] $Mode) {
    $requestFile = Join-Path $fixture 'request.json'
    $request = @{ Action = $Mode; InstallDir = $ctx.InstallDir; DataDir = $ctx.DataDir; PackagePath = $ctx.PackagePath; VaultDir = $ctx.VaultDir }
    [IO.File]::WriteAllText($requestFile, ($request | ConvertTo-Json))
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot '..\MOsuOffline.Firewall.ps1') -RequestFile $requestFile
    if ($LASTEXITCODE -ne 0) { throw "Helper $Mode en echec." }
    $helperResult = Get-Content -LiteralPath ($requestFile + '.result') -Raw | ConvertFrom-Json
    if ($helperResult.Success -ne $true) { throw $helperResult.Error }
}
$result = @{ Validated = $false; Utc = [DateTime]::UtcNow.ToString('o'); Probe = 'TCP api.nuget.org:443'; Error = '' }
$sentinel = $ctx.RuleGroup + '-foreign-sentinel'
try {
    Assert-FirewallEnabled
    & $ctx.GamePath
    if ($LASTEXITCODE -ne 0) { throw 'Connexion initiale impossible : test non concluant, pas de validation.' }
    New-NetFirewallRule -Name $sentinel -DisplayName 'MOsu Offline integration sentinel' -Group ($ctx.RuleGroup + '-foreign') -Program $ctx.GamePath -Direction Outbound -Action Allow -Profile Any -ErrorAction Stop | Out-Null
    Invoke-TestHelper 'Offline'
    if (!(Test-Path -LiteralPath $ctx.DllPath)) { throw 'DLL non installee dans la fixture.' }
    Assert-NetworkBlocked $ctx
    & $ctx.GamePath
    if ($LASTEXITCODE -ne 3) { throw 'La sonde a pu se connecter malgre le blocage.' }
    Invoke-TestHelper 'Online'
    if (Test-Path -LiteralPath $ctx.DllPath) { throw 'DLL encore presente dans la fixture.' }
    if (@(Get-OwnedFirewallRules $ctx).Count -ne 0) { throw 'Regles de test residuelles.' }
    if (!(Get-NetFirewallRule -Name $sentinel -ErrorAction Stop)) { throw 'Une regle tierce a ete supprimee.' }
    & $ctx.GamePath
    if ($LASTEXITCODE -ne 0) { throw 'Connexion non retablie apres retrait du blocage.' }
    $result.Validated = $true
} catch {
    $result.Error = $_.Exception.Message
} finally {
    # Only this fixture's rules are removed, even if a test assertion failed.
    foreach ($rule in @(Get-NetFirewallRule -ErrorAction Stop | Where-Object { $_.Group -eq $ctx.RuleGroup -or ($_.Name -eq $sentinel -and $_.Group -eq ($ctx.RuleGroup + '-foreign')) })) {
        Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
    }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $resolved = (Resolve-Path -LiteralPath $fixture).ProviderPath
    if ($resolved -ne [IO.Path]::GetFullPath($fixture) -or !(Split-Path $resolved -Leaf).StartsWith('MOsuOffline-firewall-')) { throw 'Nettoyage temporaire refuse.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
if (!$result.Validated) { throw $result.Error }
Write-Host 'PASS pare-feu Windows : connexion initiale, blocage, retour reseau et preservation regle tierce.'
