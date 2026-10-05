param(
    [ValidateSet('Menu', 'Offline', 'Online', 'Status')] [string] $Action = 'Menu',
    [string] $InstallDir = (Join-Path $env:LOCALAPPDATA 'osulazer'),
    [string] $DataDir = (Join-Path $env:APPDATA 'osu'),
    [string] $PackagePath = (Join-Path $PSScriptRoot 'package\osu.Game.Rulesets.MOsu.dll'),
    [string] $VaultDir = (Join-Path $env:LOCALAPPDATA 'MOsuOfflineManager'),
    [switch] $NoLaunch
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MOsuOffline.Core.psm1') -Force

function Invoke-FirewallHelper($Context, [string] $Operation) {
    [IO.Directory]::CreateDirectory($Context.VaultDir) | Out-Null
    $requestFile = Join-Path $Context.VaultDir ([Guid]::NewGuid().ToString('N') + '.request.json')
    $request = @{ Action = $Operation; InstallDir = $Context.InstallDir; DataDir = $Context.DataDir; PackagePath = $Context.PackagePath; VaultDir = $Context.VaultDir }
    [IO.File]::WriteAllText($requestFile, ($request | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $helper = Join-Path $PSScriptRoot 'MOsuOffline.Firewall.ps1'
    # Single-quoted literals are escaped before encoding; no string-built shell paths.
    $command = "& '" + $helper.Replace("'", "''") + "' -RequestFile '" + $requestFile.Replace("'", "''") + "'"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    try {
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $helperProcess = Start-Process -FilePath $powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-EncodedCommand', $encoded) -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        if (!(Test-Path -LiteralPath ($requestFile + '.result'))) { throw 'Diagnostic administrateur absent. Aucune bascule validée.' }
        $result = Get-Content -LiteralPath ($requestFile + '.result') -Raw | ConvertFrom-Json
        if ($helperProcess.ExitCode -ne 0 -or !$result.Success) { throw $result.Error }
        return $result
    } finally {
        Remove-Item -LiteralPath $requestFile, ($requestFile + '.result') -Force -ErrorAction SilentlyContinue
    }
}

function Start-OfflineLazer($Context) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Relancez le gestionnaire sans droits administrateur. Le jeu ne sera pas lancé avec élévation.'
    }
    Assert-LazerClosed $Context
    Invoke-FirewallHelper $Context 'Verify' | Out-Null
    Write-Host 'Premier lancement : la compatibilité ne sera confirmée que si le client charge réellement la DLL. En cas de refus, le réseau restera bloqué.'
    $session = [Guid]::NewGuid().ToString('N')
    $ready = Join-Path $Context.VaultDir ($session + '.ready')
    $oldReady = $env:MOSU_OFFLINE_READY_FILE
    $oldSession = $env:MOSU_OFFLINE_SESSION
    try {
        $env:MOSU_OFFLINE_READY_FILE = $ready
        $env:MOSU_OFFLINE_SESSION = $session
        $game = Start-Process -FilePath $Context.GamePath -WorkingDirectory (Split-Path $Context.GamePath) -PassThru
    } finally {
        $env:MOSU_OFFLINE_READY_FILE = $oldReady
        $env:MOSU_OFFLINE_SESSION = $oldSession
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $ready) {
            $message = @(Get-Content -LiteralPath $ready)
            if ($message.Count -eq 2 -and $message[0] -eq $session -and $message[1] -eq $game.Id.ToString()) {
                Write-Host 'MOsu chargé. Entraînement hors ligne actif. Retour en ligne uniquement par le gestionnaire.' -ForegroundColor Green
                Remove-Item -LiteralPath $ready -Force
                return
            }
        }
        if ($game.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    throw 'Chargement MOsu non confirmé : version incompatible, ruleset bloqué ou démarrage incomplet. Fermez lazer. Le réseau reste bloqué ; aucun contrôle du client ne sera contourné.'
}

try {
    if ($Action -eq 'Menu') {
        Write-Host 'MOsu Offline — gestionnaire de bascule'
        Write-Host '1. Activer l''entraînement hors ligne et lancer lazer'
        Write-Host '2. Retirer MOsu et revenir au jeu en ligne'
        Write-Host '3. Diagnostic du mode et des protections'
        Write-Host '0. Quitter'
        switch (Read-Host 'Choix') { '1' { $Action = 'Offline' }; '2' { $Action = 'Online' }; '3' { $Action = 'Status' }; '0' { return }; default { throw 'Choix invalide.' } }
        if (!(Test-Path -LiteralPath (Join-Path $InstallDir 'current\osu!.exe'))) { $InstallDir = Read-Host 'Dossier d''installation lazer (contenant current)' }
        if (!(Test-Path -LiteralPath $DataDir)) { $DataDir = Read-Host 'Dossier de données lazer (Ouvrir le dossier osu! dans les paramètres)' }
    }
    $context = New-OfflineContext $InstallDir $DataDir $PackagePath $VaultDir
    $mutex = [Threading.Mutex]::new($false, 'Local\' + $context.RuleGroup + '-UI')
    if (!$mutex.WaitOne(0)) { throw 'Une autre bascule est déjà en cours.' }
    try {
        if ($Action -eq 'Status') {
            $status = Invoke-FirewallHelper $context 'Status'
            $installed = Test-Path -LiteralPath $context.DllPath
            Assert-NoAdditionalMosuCopies $context
            if ($installed) { Assert-OwnedDll $context }
            $mode = if ($installed -and $status.Blocked) { 'Hors ligne protégé' } elseif (!$installed -and $status.RuleCount -eq 0) { 'MOsu retiré / mode en ligne' } else { 'État incomplet : ne pas lancer le jeu' }
            Write-Host "Mode : $mode"
            Write-Host "DLL installée : $installed ; protection complète : $($status.Blocked) ; règles gérées : $($status.RuleCount)"
            foreach ($exe in $context.Executables) { Write-Host "Exécutable vérifié : $exe" }
            return
        }
        if ($Action -eq 'Offline') {
            Assert-PackageValidated $context
        }
        Invoke-FirewallHelper $context $Action | Out-Null
        if ($Action -eq 'Offline' -and !$NoLaunch) { Start-OfflineLazer $context }
        elseif ($Action -eq 'Online') { Write-Host 'MOsu retiré et règles du gestionnaire retirées. Vous pouvez lancer lazer normalement et vous reconnecter manuellement.' }
    } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
