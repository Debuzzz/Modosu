param([string] $OutputPath)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\ModosuOffline.Core.psm1') -Force
function Assert-True($Condition, [string] $Message) { if (!$Condition) { throw $Message } }
function Assert-Throws([scriptblock] $Action) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert-True $failed 'Une operation dangereuse aurait du etre refusee.'
}
$script:passed = 0
function Test-Case([string] $Name, [scriptblock] $Body) {
    $script:state = @{ Blocked = $false; Running = $false; VerifyCount = 0; Failure = ''; Events = [Collections.Generic.List[string]]::new() }
    $caseDir = Join-Path $testRoot ([Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory((Join-Path $caseDir 'lazer\current')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $caseDir 'package')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $caseDir 'lazer\current\osu!.exe'), 'fake-executable')
    [IO.File]::WriteAllText((Join-Path $caseDir 'package\osu.Game.Rulesets.Modosu.dll'), 'test-dll')
    $script:context = New-OfflineContext (Join-Path $caseDir 'lazer') (Join-Path $caseDir 'data') (Join-Path $caseDir 'package\osu.Game.Rulesets.Modosu.dll') (Join-Path $caseDir 'vault')
    $script:ops = @{
        AssertClosed = { param($c) if ($script:state.Running) { throw 'Processus actif.' } }
        Block = { param($c) if ($script:state.Failure -in @('Permission', 'FirewallDisabled')) { throw 'Protection refusee.' }; $script:state.Blocked = $true; $script:state.Events.Add('Block') }
        Verify = { param($c) $script:state.VerifyCount++; if (!$script:state.Blocked -or $script:state.Failure -eq ('Verify' + $script:state.VerifyCount)) { throw 'Verification refusee.' }; $script:state.Events.Add('Verify') }
        Unblock = { param($c) Assert-True (!(Test-Path -LiteralPath $c.DllPath) -and !(Test-Path -LiteralPath $c.LegacyDllPath)) 'Deblocage avant retrait DLL'; if ($script:state.Failure -eq 'Unblock') { throw 'Echec retrait regles.' }; $script:state.Blocked = $false; $script:state.Events.Add('Unblock') }
    }
    & $Body
    $script:passed++
    Write-Host "PASS $Name"
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ModosuOffline-tests-' + [Guid]::NewGuid().ToString('N'))
function Initialize-LegacyInstallation {
    [IO.Directory]::CreateDirectory($context.RulesetsDir) | Out-Null
    [IO.File]::WriteAllText($context.LegacyDllPath, 'legacy-owned-dll')
    $context.RuleGroup = $context.RuleGroup.Replace('ModosuOffline-', 'MOsuOffline-')
    Save-OfflineState $context 'Offline' (Get-FileHash -LiteralPath $context.LegacyDllPath).Hash
    $script:context = New-OfflineContext $context.InstallDir $context.DataDir $context.PackagePath $context.VaultDir
    Assert-True ($context.RuleGroup.StartsWith('MOsuOffline-')) 'Anciennes regles abandonnees'
    $state.Blocked = $true
}
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
try {
    Test-Case 'Bascule repetee sans perte de donnees' {
        [IO.Directory]::CreateDirectory($context.DataDir) | Out-Null
        $profile = Join-Path $context.DataDir 'client.realm'
        [IO.File]::WriteAllText($profile, 'keep-profile-and-scores')
        1..3 | ForEach-Object {
            Invoke-OfflineTransition $context Offline $ops
            Assert-True $state.Blocked 'Reseau non bloque'
            Assert-True (Test-Path -LiteralPath $context.DllPath) 'DLL absente'
            Assert-True ((Get-OfflineState $context).Mode -eq 'Offline') 'Journal incorrect'
            Invoke-OfflineTransition $context Online $ops
            Assert-True (!$state.Blocked) 'Regles non retirees'
            Assert-True (!(Test-Path -LiteralPath $context.DllPath)) 'DLL encore installee'
        }
        Assert-True ((Get-Content -LiteralPath $profile -Raw) -eq 'keep-profile-and-scores') 'Donnees alterees'
    }
    foreach ($reason in @('Permission', 'FirewallDisabled')) {
        Test-Case $reason {
            $state.Failure = $reason
            Assert-Throws { Invoke-OfflineTransition $context Offline $ops }
            Assert-True (!(Test-Path -LiteralPath $context.DllPath)) 'DLL installee sans protection'
        }
    }
    Test-Case 'Jeu actif' {
        $state.Running = $true
        Assert-Throws { Invoke-OfflineTransition $context Offline $ops }
        Assert-True ($state.Events.Count -eq 0) 'Mutation malgre processus actif'
    }
    foreach ($checkpoint in @('Verify1', 'Verify2')) {
        Test-Case "Interruption $checkpoint" {
            $state.Failure = $checkpoint
            Assert-Throws { Invoke-OfflineTransition $context Offline $ops }
            Assert-True $state.Blocked 'Blocage perdu apres interruption'
            $state.Failure = ''
            Invoke-OfflineTransition $context Online $ops
            Assert-True (!$state.Blocked -and !(Test-Path -LiteralPath $context.DllPath)) 'Recuperation impossible'
        }
    }
    Test-Case 'DLL preexistante non ecrasee' {
        [IO.Directory]::CreateDirectory($context.RulesetsDir) | Out-Null
        [IO.File]::WriteAllText($context.DllPath, 'foreign-dll')
        Assert-Throws { Invoke-OfflineTransition $context Offline $ops }
        Assert-Throws { Invoke-OfflineTransition $context Online $ops }
        Assert-True ((Get-Content -LiteralPath $context.DllPath -Raw) -eq 'foreign-dll') 'DLL tierce alteree'
    }
    Test-Case 'Echec retour en ligne garde le blocage' {
        Invoke-OfflineTransition $context Offline $ops
        $state.Failure = 'Unblock'
        Assert-Throws { Invoke-OfflineTransition $context Online $ops }
        Assert-True $state.Blocked 'Blocage perdu'
        Assert-True (!(Test-Path -LiteralPath $context.DllPath)) 'DLL pas retiree'
    }
    Test-Case 'Processus demarre pendant retrait' {
        Invoke-OfflineTransition $context Offline $ops
        $script:closedCalls = 0
        $ops.AssertClosed = { param($c) $script:closedCalls++; if ($script:closedCalls -gt 1) { throw 'Nouveau processus.' } }
        Assert-Throws { Invoke-OfflineTransition $context Online $ops }
        Assert-True $state.Blocked 'Deblocage avec processus concurrent'
    }
    Test-Case 'Stockage dans rulesets refuse' {
        Assert-Throws { New-OfflineContext $context.InstallDir $context.DataDir $context.PackagePath $context.RulesetsDir }
    }
    foreach ($checkpoint in @('Blocked', 'VerifiedBeforeInstall', 'InstallJournaled', 'Staged', 'Installed', 'VerifiedAfterInstall', 'OfflineJournaled')) {
        Test-Case "Interruption entrainement apres $checkpoint" {
            $script:failAt = $checkpoint
            $ops.Checkpoint = { param($name) if ($name -eq $script:failAt) { throw 'Interruption injectee.' } }
            Assert-Throws { Invoke-OfflineTransition $context Offline $ops }
            Assert-True $state.Blocked 'Interruption a debloque le reseau'
            $ops.Remove('Checkpoint')
            Invoke-OfflineTransition $context Online $ops
            Assert-True (!(Test-Path -LiteralPath $context.DllPath) -and !$state.Blocked) 'Recuperation impossible'
        }
    }
    foreach ($checkpoint in @('RemoveJournaled', 'Parked', 'Removed', 'ClosedBeforeUnblock', 'Unblocked', 'OnlineJournaled')) {
        Test-Case "Interruption retour apres $checkpoint" {
            Invoke-OfflineTransition $context Offline $ops
            $script:failAt = $checkpoint
            $ops.Checkpoint = { param($name) if ($name -eq $script:failAt) { throw 'Interruption injectee.' } }
            Assert-Throws { Invoke-OfflineTransition $context Online $ops }
            Assert-True $state.Blocked 'Interruption a laisse le reseau debloque'
            $ops.Remove('Checkpoint')
            Invoke-OfflineTransition $context Online $ops
            Assert-True (!(Test-Path -LiteralPath $context.DllPath) -and !$state.Blocked) 'Recuperation impossible'
        }
    }
    Test-Case 'Copie supplementaire Modosu detectee sans execution' {
        $dll = Join-Path $PSScriptRoot '..\..\osu.Game.Rulesets.Modosu\bin\Release\net10.0\osu.Game.Rulesets.Modosu.dll'
        [IO.Directory]::CreateDirectory($context.RulesetsDir) | Out-Null
        $extra = Join-Path $context.RulesetsDir 'osu.Game.Rulesets.OtherName.dll'
        Copy-Item -LiteralPath $dll -Destination $extra
        Assert-Throws { Invoke-OfflineTransition $context Offline $ops }
        Assert-Throws { Invoke-OfflineTransition $context Online $ops }
        Assert-True (Test-Path -LiteralPath $extra) 'Copie non geree modifiee'
    }
    Test-Case 'Migration MOsu vers Modosu sans deblocage' {
        Initialize-LegacyInstallation
        $oldHash = (Get-OfflineState $context).DllHash
        Invoke-OfflineTransition $context Offline $ops
        Assert-True ($state.Blocked -and (Test-Path -LiteralPath $context.DllPath) -and !(Test-Path -LiteralPath $context.LegacyDllPath)) 'Migration incomplete'
        Assert-True (Test-Path -LiteralPath (Join-Path $context.VaultDir ('parked-' + $oldHash + '.dll'))) 'Ancienne DLL non sauvegardee'
        $script:context = New-OfflineContext $context.InstallDir $context.DataDir $context.PackagePath $context.VaultDir
        Assert-True ($context.RuleGroup.StartsWith('MOsuOffline-')) 'Ancien groupe perdu apres migration'
        Invoke-OfflineTransition $context Online $ops
        Assert-True (!$state.Blocked) 'Ancien blocage non retire'
    }
    Test-Case 'Retour en ligne depuis ancienne installation geree' {
        Initialize-LegacyInstallation
        Invoke-OfflineTransition $context Online $ops
        Assert-True (!(Test-Path -LiteralPath $context.LegacyDllPath) -and !$state.Blocked) 'Ancienne installation non retiree'
    }
    Test-Case 'Ancienne DLL sans journal refusee' {
        [IO.Directory]::CreateDirectory($context.RulesetsDir) | Out-Null
        [IO.File]::WriteAllText($context.LegacyDllPath, 'unknown-legacy-dll')
        Assert-Throws { Invoke-OfflineTransition $context Offline $ops }
        Assert-Throws { Invoke-OfflineTransition $context Online $ops }
        Assert-True ((Get-Content -LiteralPath $context.LegacyDllPath -Raw) -eq 'unknown-legacy-dll') 'Ancienne DLL tierce modifiee'
    }
    foreach ($checkpoint in @('LegacyParked', 'LegacyRemoved')) {
        Test-Case "Interruption migration apres $checkpoint" {
            Initialize-LegacyInstallation
            $script:failAt = $checkpoint
            $ops.Checkpoint = { param($name) if ($name -eq $script:failAt) { throw 'Interruption migration injectee.' } }
            Assert-Throws { Invoke-OfflineTransition $context Offline $ops }
            Assert-True $state.Blocked 'Migration interrompue a debloque le reseau'
            $ops.Remove('Checkpoint')
            Invoke-OfflineTransition $context Online $ops
            Assert-True (!(Test-Path -LiteralPath $context.LegacyDllPath) -and !(Test-Path -LiteralPath $context.DllPath) -and !$state.Blocked) 'Recuperation migration impossible'
        }
    }
    if ($OutputPath) {
        $report = @{ Passed = $passed; Success = $true; Utc = [DateTime]::UtcNow.ToString('o'); CoreSha256 = (Get-FileHash (Join-Path $PSScriptRoot '..\ModosuOffline.Core.psm1')).Hash }
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($report | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    }
    Write-Host "$passed tests de transition reussis (operations reseau simulees)."
} finally {
    $resolved = (Resolve-Path -LiteralPath $testRoot).ProviderPath
    if ($resolved -ne [IO.Path]::GetFullPath($testRoot) -or !(Split-Path $resolved -Leaf).StartsWith('ModosuOffline-tests-')) { throw 'Nettoyage temporaire refuse.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
