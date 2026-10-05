# Validation du paquet Windows Modosu

Contrôles terminés le 5 octobre 2026, via `manager/Validate-Package.ps1`, Windows PowerShell 5.1 et .NET 10. Aucun déploiement dans le jeu de l'utilisateur.

| Contrôle | Résultat |
|---|---|
| Restauration et compilation Release | Réussite ; 3 avertissements nullable existants dans le test des replays |
| NUnit | 13 tests réussis : identité personnalisée, flags des mods, déconnexion et reconnexion, transformations locales RandomV2/CircleGeneration, restauration des objets, SpacingAdjust |
| Bascule PowerShell | 29 scénarios réussis sur dossiers temporaires : répétitions, refus des droits, pare-feu désactivé, jeu actif, nouvelle ouverture pendant le retrait, DLL étrangère/renommée, migration depuis MOsu, interruptions après chaque mutation et reprise |
| Tests visuels | Imports JSON/cartes et anciens préréglages, migration des paramètres/profils/scores/préréglages sans perte des références de replay, profils et scores locaux, RandomV2, CircleGeneration, enregistrement et lecture des replays réussis ; captures inspectées |
| Pare-feu réel | Sonde temporaire : connexion TCP initiale, blocage après bascule hors ligne par le helper réel, DLL présente dans la fixture, retrait par le helper, DLL absente, connexion rétablie ; même contrôle après migration d'un ancien journal MOsu et de ses règles ; règle témoin préservée et nettoyage des règles de test |
| Client officiel installé | **Modosu non validé** : aucune installation ni tentative de chargement de la nouvelle DLL dans le jeu de l'utilisateur |

Les sept scènes sont `TestSceneCollectionImport`, `TestSceneUserProfileOverlay`, `TestSceneReplayPersistence`, `TestSceneAutoplayRandomV2`, `TestSceneOsuModRandomV2`, `TestSceneLegacyDataMigration`, `TestSceneModPresetImport`. Elles utilisent une API factice et des données temporaires ; les caches du lanceur sont isolés. La sonde communique seulement avec `api.nuget.org:443`, sans compte ni endpoint osu!.

Les interruptions sont injectées sous forme d'exceptions entre les étapes. Les refus UAC et le pare-feu désactivé sont simulés dans ces tests ; aucune désactivation du pare-feu réel n'a été nécessaire. Une coupure d'alimentation ou un arrêt forcé du processus administrateur pendant un appel système n'est pas couvert par ces injections : après cela, le diagnostic doit revérifier la protection réelle avant tout lancement.

La copie d'encodage du replay utilise osu!standard uniquement pour produire le `.osr`. Le test vérifie que le score enregistré conserve `modosu` et `OnlineID = -1`, et que son replay peut être relu.

Les rapports locaux sont dans `.cache/offline-validation`, les captures dans `screenshots`. Le fichier `package/validation.json` lie le résultat à la DLL et au module PowerShell par SHA-256. Une nouvelle compilation simple remet le verrou en place ; exécuter la validation avant une nouvelle livraison.

Ce rapport ne constitue ni une approbation d'osu! ni une garantie de compatibilité avec le client installé. Le premier lancement doit rester protégé et confirmer le chargement réel. Un refus conserve le blocage et doit être traité comme une incompatibilité.
