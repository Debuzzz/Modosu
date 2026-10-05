# MOsu Offline — entraînement local

Fork de [p-720/mosu](https://github.com/p-720/mosu) pour Windows, avec une bascule manuelle sur un seul client osu!lazer.

- **Entraînement hors ligne** : blocage réseau du client et de ses exécutables de mise à jour, puis installation de la DLL.
- **Jeu en ligne** : retrait de la DLL, puis retrait des seules règles de pare-feu du gestionnaire, jeu fermé.

RandomV2, CircleGeneration, imports locaux, profils, scores, statistiques après partie et replays locaux sont conservés. Le partage dans le chat, les suggestions en ligne, les téléchargements automatiques et les compteurs personnalisés PP/étoiles en direct sont retirés. Les mods personnalisés sont explicitement non classés et exclus du multijoueur. L’identité technique MOsu et les licences restent inchangées.

**Aucune DLL ne doit être installée manuellement dans le jeu.** Lire le [guide du gestionnaire](manager/GUIDE.md). La DLL seule ne bloque pas toutes les communications : le pare-feu externe est indispensable.

## Construire et valider

Cloner avec le sous-module `osu` (`git clone --recurse-submodules`). Installer .NET 10 puis, dans PowerShell :

```powershell
dotnet restore OsuRuleset.sln --packages .cache/nuget
powershell -NoProfile -ExecutionPolicy RemoteSigned -File manager/Validate-Package.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File manager/Build-Bundle.ps1
```

L’archive est `artifacts/MOsuOffline-Windows.zip`. La compilation seule (`Build-Package.ps1`) et l’artefact GitHub Actions produisent un paquet verrouillé en attendant les contrôles Windows. La validation ne touche pas l’installation du jeu. [Rapport de validation de cette version](manager/VALIDATION.md).

Le [paquet Windows de cette livraison](delivery/MOsuOffline-Windows.zip) contient la DLL et le gestionnaire validés sur les contrôles décrits dans ce rapport. Le chargement par le client officiel reste à confirmer.

## Compatibilité

Le client officiel doit accepter le ruleset sans modification de ses contrôles. Le gestionnaire exige une confirmation réelle de chargement lors du lancement protégé ; sinon il signale une incompatibilité et garde le réseau bloqué. Cette version ne garantit ni une compatibilité avec les nouvelles versions de lazer ni une approbation par l’équipe osu!.

Les informations, attributions et captures historiques du projet original sont conservées dans [README.upstream.md](README.upstream.md). Ce document décrit l’ancienne version et ses instructions d’installation ne s’appliquent pas à ce fork.
