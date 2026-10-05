param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$results = Join-Path $repo '.cache\offline-validation'
[IO.Directory]::CreateDirectory($results) | Out-Null
Push-Location $repo
try {
    & dotnet build OsuRuleset.sln --no-restore -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Compilation refusee.' }
    & (Join-Path $PSScriptRoot 'Build-Package.ps1')
    & dotnet test osu.Game.Rulesets.MOsu.Tests/osu.Game.Rulesets.MOsu.Tests.csproj --no-build --no-restore -c Release --filter 'FullyQualifiedName~OfflinePolicyTest|FullyQualifiedName~OriginalStateStoreTest|FullyQualifiedName~SpacingAdjustTest' --logger 'trx;LogFileName=unit.trx' --results-directory $results
    if ($LASTEXITCODE -ne 0) { throw 'Tests NUnit en echec.' }
    & (Join-Path $PSScriptRoot 'tests\Test-Transitions.ps1') -OutputPath (Join-Path $results 'transitions.json')
    foreach ($scene in @('TestSceneCollectionImport', 'TestSceneUserProfileOverlay', 'TestSceneReplayPersistence', 'TestSceneAutoplayRandomV2', 'TestSceneOsuModRandomV2')) {
        $log = Join-Path $results ($scene + '.log')
        & dotnet run --project osu.Game.Rulesets.MOsu.Tests/osu.Game.Rulesets.MOsu.Tests.csproj --no-restore -- --auto --filter $scene *> $log
        if ($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch "[ScreenshotTestRunner] Completed: $scene" -Quiet)) { throw "Test visuel en echec : $scene. Consultez $log" }
        if (!(Test-Path -LiteralPath (Join-Path $repo "screenshots\$scene.png"))) { throw "Capture absente : $scene" }
    }
    & dotnet build manager/tests/FirewallProbe/FirewallProbe.csproj -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Compilation sonde refusee.' }
    & (Join-Path $PSScriptRoot 'tests\Run-FirewallValidation.ps1') -OutputPath (Join-Path $results 'firewall.json')
    if ($LASTEXITCODE -ne 0) { throw 'Validation pare-feu en echec.' }
    $firewall = Get-Content -LiteralPath (Join-Path $results 'firewall.json') -Raw | ConvertFrom-Json
    if ($firewall.Validated -ne $true) { throw 'Rapport pare-feu non concluant.' }
    $package = Join-Path $PSScriptRoot 'package'
    $receipt = Get-Content -LiteralPath (Join-Path $package 'validation.json') -Raw | ConvertFrom-Json
    $receipt.ControlsValidated = $true
    $receipt.Note = 'NUnit, transitions avec interruptions, scenes locales et sonde Windows valides. Compatibilite du client officiel non testee ; confirmation exigee au lancement protege.'
    $receipt | Add-Member -NotePropertyName ValidatedUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $receipt | Add-Member -NotePropertyName CoreSha256 -NotePropertyValue ((Get-FileHash (Join-Path $PSScriptRoot 'MOsuOffline.Core.psm1')).Hash) -Force
    [IO.File]::WriteAllText((Join-Path $package 'validation.json'), ($receipt | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Write-Host 'Controles automatiques reussis. Inspectez les captures dans screenshots. Aucune installation dans votre jeu.'
} finally { Pop-Location }
