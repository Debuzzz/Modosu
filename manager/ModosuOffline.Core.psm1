Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CanonicalPath([string] $Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Chemin vide.' }
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Get-PathDigest([string] $Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())))).Replace('-', '').Substring(0, 20) }
    finally { $sha.Dispose() }
}

function Assert-NoSymbolicLink([string] $Path) {
    $part = Get-CanonicalPath $Path
    while ($part) {
        if (Test-Path -LiteralPath $part) {
            $item = Get-Item -LiteralPath $part -Force
            if ($item.LinkType) { throw "Lien symbolique non autorisé : $part" }
        }
        $parent = [IO.Path]::GetDirectoryName($part)
        if ($parent -eq $part) { break }
        $part = $parent
    }
}

function New-OfflineContext {
    param([string] $InstallDir, [string] $DataDir, [string] $PackagePath, [string] $VaultDir)
    $install = Get-CanonicalPath $InstallDir
    $data = Get-CanonicalPath $DataDir
    $package = Get-CanonicalPath $PackagePath
    $vault = Get-CanonicalPath $VaultDir
    $rulesets = Join-Path $data 'rulesets'
    foreach ($path in @($install, $data, $package, $vault, $rulesets)) { Assert-NoSymbolicLink $path }
    if ($vault -eq $rulesets -or $vault.StartsWith($rulesets + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $package -eq $rulesets -or $package.StartsWith($rulesets + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Le stockage et le paquet doivent être hors du dossier rulesets.'
    }
    $game = Join-Path $install 'current\osu!.exe'
    if (!(Test-Path -LiteralPath $game -PathType Leaf)) { throw "Installation lazer introuvable : $game" }
    $executables = @(Get-ChildItem -LiteralPath $install -Filter '*.exe' -File -Recurse -ErrorAction Stop |
        ForEach-Object { Assert-NoSymbolicLink $_.FullName; $_.FullName } | Sort-Object -Unique)
    if ($executables.Count -eq 0) { throw 'Aucun exécutable à protéger.' }
    $digest = Get-PathDigest ($install + '|' + $data)
    $group = 'ModosuOffline-' + $digest
    $legacyGroup = 'MOsuOffline-' + $digest
    $legacyDll = Join-Path $rulesets 'osu.Game.Rulesets.MOsu.dll'
    $dll = Join-Path $rulesets 'osu.Game.Rulesets.Modosu.dll'
    $stateFile = Join-Path $vault 'state.json'
    if (Test-Path -LiteralPath $stateFile) {
        $previous = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        if ($previous.RuleGroup -eq $legacyGroup -and $previous.DllPath -in @($legacyDll, $dll)) {
            # Keep existing rule names/mutexes until their manual removal. Never orphan a block.
            $group = $legacyGroup
        }
    }
    return [pscustomobject]@{
        InstallDir = $install; DataDir = $data; PackagePath = $package; VaultDir = $vault
        RulesetsDir = $rulesets; DllPath = $dll; LegacyDllPath = $legacyDll
        StateFile = $stateFile; GamePath = $game
        Executables = $executables; RuleGroup = $group
    }
}

function Assert-LazerClosed($Context) {
    $names = @($Context.Executables | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }) + @('osu!', 'osu', 'Update')
    foreach ($process in Get-Process -ErrorAction Stop) {
        # Access to a matching process must be verifiable. Do not assume an inaccessible
        # osu! process is safe. Stable may run elsewhere, but unverifiable matches stop us.
        if ($process.ProcessName -notin $names) { continue }
        try { $path = $process.Path } catch { throw 'Impossible de vérifier les processus osu!. Fermez le jeu et réessayez.' }
        if (!$path) { throw 'Un processus osu!/Update inaccessible est actif.' }
        if ($path.StartsWith($Context.InstallDir + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Fermez osu!lazer et son programme de mise à jour avant la bascule.'
        }
    }
}

function Get-OwnedFirewallRules($Context) {
    # Enumerate explicitly: a failed/denied query must never mean "no rules".
    return @(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop |
        Where-Object { $_.Group -eq $Context.RuleGroup })
}

function Assert-FirewallEnabled {
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    if ($profiles.Count -ne 3 -or @($profiles | Where-Object { $_.Enabled -ne $true }).Count -gt 0) {
        throw 'Le pare-feu doit être activé sur les profils Domaine, Privé et Public. Aucune activation automatique.'
    }
}

function Get-RuleName($Context, [string] $Executable, [string] $Direction) {
    return $Context.RuleGroup + '-' + (Get-PathDigest $Executable) + '-' + $Direction
}

function Test-RuleProtection($Rule, [string] $Executable, [string] $Direction) {
    $program = @($Rule | Get-NetFirewallApplicationFilter -ErrorAction Stop)
    $ports = @($Rule | Get-NetFirewallPortFilter -ErrorAction Stop)
    $addresses = @($Rule | Get-NetFirewallAddressFilter -ErrorAction Stop)
    return $Rule.Enabled -eq 'True' -and $Rule.Action -eq 'Block' -and $Rule.Direction -eq $Direction -and
        $Rule.Profile.ToString() -eq 'Any' -and $program.Count -eq 1 -and $program[0].Program -eq $Executable -and
        $ports.Count -eq 1 -and $ports[0].Protocol -eq 'Any' -and $ports[0].LocalPort -eq 'Any' -and $ports[0].RemotePort -eq 'Any' -and
        $addresses.Count -eq 1 -and $addresses[0].RemoteAddress -eq 'Any' -and $addresses[0].LocalAddress -eq 'Any'
}

function Assert-NetworkBlocked($Context) {
    Assert-FirewallEnabled
    $rules = @(Get-OwnedFirewallRules $Context)
    foreach ($exe in $Context.Executables) {
        foreach ($direction in @('Inbound', 'Outbound')) {
            $name = Get-RuleName $Context $exe $direction
            $rule = @($rules | Where-Object { $_.Name -eq $name })
            if ($rule.Count -ne 1 -or !(Test-RuleProtection $rule[0] $exe $direction)) {
                throw "Protection réseau absente ou incomplète : $exe ($direction)."
            }
        }
    }
}

function Enable-NetworkBlock($Context) {
    Assert-LazerClosed $Context
    Assert-FirewallEnabled
    $allRules = @(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop)
    foreach ($exe in $Context.Executables) {
        foreach ($direction in @('Inbound', 'Outbound')) {
            $name = Get-RuleName $Context $exe $direction
            $existing = @($allRules | Where-Object { $_.Name -eq $name })
            if ($existing.Count -gt 0) {
                if ($existing.Count -ne 1 -or $existing[0].Group -ne $Context.RuleGroup -or !(Test-RuleProtection $existing[0] $exe $direction)) {
                    throw "Règle conflictuelle : $name. Aucune règle existante modifiée."
                }
            } else {
                New-NetFirewallRule -Name $name -DisplayName "Modosu Offline : $direction $exe" -Group $Context.RuleGroup `
                    -Program $exe -Direction $direction -Action Block -Enabled True -Profile Any -Protocol Any -ErrorAction Stop | Out-Null
            }
        }
    }
    Assert-NetworkBlocked $Context
}

function Disable-NetworkBlock($Context) {
    Assert-LazerClosed $Context
    if ((Test-Path -LiteralPath $Context.DllPath) -or (Test-Path -LiteralPath $Context.LegacyDllPath)) { throw 'Une DLL de pratique est encore installée. Le réseau reste bloqué.' }
    Assert-NoAdditionalModosuCopies $Context
    $rules = @(Get-OwnedFirewallRules $Context)
    foreach ($rule in $rules) {
        if (!$rule.Name.StartsWith($Context.RuleGroup + '-', [StringComparison]::Ordinal)) { throw 'Règle de propriété ambiguë.' }
    }
    Assert-LazerClosed $Context
    foreach ($rule in $rules) {
        Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
    }
    if (@(Get-OwnedFirewallRules $Context).Count -ne 0) { throw 'Certaines règles de blocage restent actives.' }
}

function Save-OfflineState($Context, [string] $Mode, [string] $DllHash) {
    [IO.Directory]::CreateDirectory($Context.VaultDir) | Out-Null
    $recordPath = if (Test-Path -LiteralPath $Context.LegacyDllPath) { $Context.LegacyDllPath } else { $Context.DllPath }
    $state = @{ Mode = $Mode; DllHash = $DllHash; DllPath = $recordPath; RuleGroup = $Context.RuleGroup; UpdatedUtc = [DateTime]::UtcNow.ToString('o') }
    $temp = $Context.StateFile + '.tmp'
    [IO.File]::WriteAllText($temp, ($state | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $Context.StateFile -Force
}

function Get-OfflineState($Context) {
    if (!(Test-Path -LiteralPath $Context.StateFile -PathType Leaf)) { return $null }
    $state = Get-Content -LiteralPath $Context.StateFile -Raw | ConvertFrom-Json
    if ($state.DllPath -notin @($Context.DllPath, $Context.LegacyDllPath) -or $state.RuleGroup -ne $Context.RuleGroup) { throw 'Le journal appartient à une autre installation.' }
    return $state
}

function Assert-OwnedDll($Context) {
    $state = Get-OfflineState $Context
    foreach ($path in @($Context.DllPath, $Context.LegacyDllPath)) {
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        Assert-NoSymbolicLink $path
        if (!$state -or $state.DllPath -ne $path -or $state.DllHash -ne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) {
            throw 'DLL de pratique préexistante ou modifiée : aucune suppression ni écrasement automatique. Le réseau reste bloqué.'
        }
    }
}

function Park-OwnedDll($Context, [string] $Path, [string] $Hash) {
    $parked = Join-Path $Context.VaultDir ('parked-' + $Hash + '.dll')
    Copy-Item -LiteralPath $Path -Destination $parked -Force
    if ((Get-FileHash -LiteralPath $parked).Hash -ne $Hash) { throw 'Sauvegarde DLL invalide.' }
    return $parked
}

function Assert-NoAdditionalModosuCopies($Context) {
    if (!(Test-Path -LiteralPath $Context.RulesetsDir)) { return }
    foreach ($dll in Get-ChildItem -LiteralPath $Context.RulesetsDir -Filter '*.dll' -File -Recurse -ErrorAction Stop) {
        if ($dll.FullName -in @($Context.DllPath, $Context.LegacyDllPath)) { continue }
        Assert-NoSymbolicLink $dll.FullName
        # Read assembly metadata only; never execute a ruleset to identify it.
        try { $assembly = [Reflection.AssemblyName]::GetAssemblyName($dll.FullName) }
        catch [BadImageFormatException] { continue }
        if ($assembly.Name -in @('osu.Game.Rulesets.Modosu', 'osu.Game.Rulesets.MOsu')) {
            throw "Autre copie Modosu détectée : $($dll.FullName). Retirez-la manuellement, jeu fermé, avant la bascule. Aucun autre fichier modifié."
        }
    }
}

function Assert-PackageValidated($Context) {
    $file = Join-Path (Split-Path $Context.PackagePath) 'validation.json'
    if (!(Test-Path -LiteralPath $file)) { throw 'Validation du paquet absente. Installation refusee.' }
    $validation = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    if ($validation.ControlsValidated -isnot [bool] -or !$validation.ControlsValidated -or $validation.DllSha256 -ne (Get-FileHash -LiteralPath $Context.PackagePath).Hash -or
        $validation.CoreSha256 -ne (Get-FileHash -LiteralPath $PSCommandPath).Hash) {
        throw 'Controles non valides pour cette DLL. Installation refusee ; consultez le guide.'
    }
}

function Invoke-TransitionCheckpoint([hashtable] $Operations, [string] $Name) {
    # Fault-injection seam for interruptions between mutations. Unused by the UI.
    if ($Operations.ContainsKey('Checkpoint')) { & $Operations.Checkpoint $Name }
}

function Invoke-OfflineTransition {
    param($Context, [ValidateSet('Offline', 'Online')] [string] $Mode, [hashtable] $Operations)
    & $Operations.AssertClosed $Context
    Assert-NoAdditionalModosuCopies $Context
    if ($Mode -eq 'Offline') {
        if (!(Test-Path -LiteralPath $Context.PackagePath -PathType Leaf)) { throw 'Paquet DLL introuvable.' }
        Assert-OwnedDll $Context
        $hash = (Get-FileHash -LiteralPath $Context.PackagePath -Algorithm SHA256).Hash
        & $Operations.Block $Context
        Invoke-TransitionCheckpoint $Operations 'Blocked'
        & $Operations.Verify $Context
        Invoke-TransitionCheckpoint $Operations 'VerifiedBeforeInstall'
        & $Operations.AssertClosed $Context
        if (Test-Path -LiteralPath $Context.LegacyDllPath) {
            $legacyState = Get-OfflineState $Context
            Save-OfflineState $Context 'RemovingLegacy' $legacyState.DllHash
            Park-OwnedDll $Context $Context.LegacyDllPath $legacyState.DllHash | Out-Null
            Invoke-TransitionCheckpoint $Operations 'LegacyParked'
            Remove-Item -LiteralPath $Context.LegacyDllPath -Force
            Invoke-TransitionCheckpoint $Operations 'LegacyRemoved'
        }
        # Journal before installation: an interrupted copy remains recoverable while blocked.
        Save-OfflineState $Context 'Installing' $hash
        Invoke-TransitionCheckpoint $Operations 'InstallJournaled'
        [IO.Directory]::CreateDirectory($Context.RulesetsDir) | Out-Null
        $staged = Join-Path $Context.RulesetsDir ([Guid]::NewGuid().ToString('N') + '.modosuoffline-pending')
        Copy-Item -LiteralPath $Context.PackagePath -Destination $staged
        if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ne $hash) { throw 'Copie DLL invalide. Réseau toujours bloqué.' }
        Invoke-TransitionCheckpoint $Operations 'Staged'
        # Rename inside rulesets is atomic; a partial copy cannot become a loadable DLL.
        Move-Item -LiteralPath $staged -Destination $Context.DllPath -Force
        Invoke-TransitionCheckpoint $Operations 'Installed'
        & $Operations.Verify $Context
        Invoke-TransitionCheckpoint $Operations 'VerifiedAfterInstall'
        Save-OfflineState $Context 'Offline' $hash
        Invoke-TransitionCheckpoint $Operations 'OfflineJournaled'
    } else {
        Assert-OwnedDll $Context
        $state = Get-OfflineState $Context
        $hash = if ($state) { $state.DllHash } else { '' }
        Save-OfflineState $Context 'Removing' $hash
        Invoke-TransitionCheckpoint $Operations 'RemoveJournaled'
        foreach ($path in @($Context.DllPath, $Context.LegacyDllPath)) {
            if (!(Test-Path -LiteralPath $path)) { continue }
            Park-OwnedDll $Context $path $hash | Out-Null
            Invoke-TransitionCheckpoint $Operations 'Parked'
            Remove-Item -LiteralPath $path -Force
            Invoke-TransitionCheckpoint $Operations 'Removed'
        }
        if ((Test-Path -LiteralPath $Context.DllPath) -or (Test-Path -LiteralPath $Context.LegacyDllPath)) { throw 'Retrait DLL incomplet.' }
        & $Operations.AssertClosed $Context
        Invoke-TransitionCheckpoint $Operations 'ClosedBeforeUnblock'
        try {
            & $Operations.Unblock $Context
            Invoke-TransitionCheckpoint $Operations 'Unblocked'
            Save-OfflineState $Context 'Online' $hash
            Invoke-TransitionCheckpoint $Operations 'OnlineJournaled'
        }
        catch {
            $failure = $_
            # Restore a complete block after a partially failed rule removal.
            # If Windows refuses this too, the DLL is already absent; report both failures.
            try { & $Operations.Block $Context; & $Operations.Verify $Context }
            catch { throw "Retour en ligne incomplet et restauration du pare-feu refusée : $($_.Exception.Message). DLL retirée ; ne relancez pas le jeu avant diagnostic." }
            throw $failure
        }
    }
}

Export-ModuleMember -Function *
