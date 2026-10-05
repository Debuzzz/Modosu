# MOsu Offline — entraînement local

Windows, PowerShell 5.1 et osu!lazer. Ce gestionnaire conserve les cartes, profils, scores et replays locaux. Le réseau est bloqué pour **tout le client**, même si vous sélectionnez ensuite un autre ruleset. Fermer lazer conserve le blocage.

## Démarrage

1. Extraire tout le paquet dans un dossier extérieur à `rulesets`. Ne pas copier la DLL manuellement dans le jeu.
2. Fermer lazer et son programme de mise à jour. Ouvrir **Lancer le gestionnaire.cmd** sans droits administrateur.
3. Choisir **1 — Entraînement hors ligne**, puis accepter les demandes Windows pour les protections. Le jeu est lancé avec les droits ordinaires.
4. Attendre la confirmation « MOsu chargé ». En cas d'incompatibilité ou de délai dépassé, fermer lazer et utiliser le diagnostic. Aucun contrôle du client officiel n'est contourné.

Le gestionnaire détecte `%LOCALAPPDATA%\osulazer` et `%APPDATA%\osu`. Il demande les chemins s'ils ont changé. Pour une installation particulière :

```powershell
.\MOsuOffline.ps1 -InstallDir 'D:\lazer' -DataDir 'D:\donnees-osu'
```

Le pare-feu Windows doit être activé sur Domaine, Privé et Public. Les règles couvrent les exécutables présents dans l'installation, y compris le lanceur et l'updater. Chaque lancement par le gestionnaire revérifie ces chemins et leurs protections. Ne pas lancer directement le jeu en entraînement, désactiver le pare-feu ou mettre à jour le client pendant cette session.

## Revenir au jeu en ligne

Fermer lazer, rouvrir le gestionnaire et choisir **2 — Jeu en ligne**. Il sauvegarde puis retire sa DLL avant de retirer ses propres règles. Il refuse la bascule si un processus est actif, si une copie supplémentaire de MOsu existe ou si la propriété de la DLL est incertaine. Les autres rulesets et règles restent en place. Ensuite lancer lazer normalement et se reconnecter manuellement.

Les deux modes utilisent le même dossier de données. La déconnexion complémentaire de MOsu efface l'authentification enregistrée ; les profils locaux restent disponibles. Importer les cartes depuis des fichiers `.osz` et les collections/préréglages depuis leurs JSON. Les calculs de statistiques après partie sont conservés. L'identité osu!standard utilisée dans une copie d'encodage `.osr` ne transforme pas les scores enregistrés en scores officiels.

## Diagnostic et récupération

Le choix **3** affiche la présence de la DLL, la protection complète, le nombre de règles et les exécutables vérifiés. Un état incomplet signifie qu'il faut garder le jeu fermé et réessayer la bascule/diagnostic. Un refus UAC ne déclenche aucun retour en ligne. Une erreur traitée après le début du retrait des règles tente de rétablir leur blocage, avec la DLL déjà retirée.

Après une coupure ou l'arrêt forcé du processus administrateur, Windows peut avoir appliqué seulement une partie des modifications. Le journal ne suffit donc jamais à prouver la protection : refaire le diagnostic avant tout lancement. Le réseau ne peut pas être garanti si un administrateur désactive le pare-feu ou si Windows refuse les règles. Ces erreurs n'entraînent aucun lancement automatique du jeu.

Le stockage est `%LOCALAPPDATA%\MOsuOfflineManager`, hors de `rulesets`. Conserver ce dossier et le gestionnaire pour pouvoir revenir en ligne. Ne supprimer ni déplacer les règles manuellement.

## Validation du paquet

Une compilation seule produit un paquet verrouillé (`ControlsValidated: false`). Le gestionnaire refuse son installation. Pour les développeurs, depuis le dépôt avec .NET 10 :

```powershell
dotnet restore OsuRuleset.sln --packages .cache/nuget
powershell -NoProfile -ExecutionPolicy RemoteSigned -File manager/Validate-Package.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File manager/Build-Bundle.ps1
```

La validation exécute NUnit, 24 scénarios de bascule, cinq scènes de tests utilisant des données temporaires et une sonde TCP vers `api.nuget.org:443`. Elle requiert une confirmation UAC pour ses seules règles temporaires. Elle vérifie connexion, blocage, retour réseau et préservation d'une règle témoin. Aucun compte osu! n'est utilisé. Inspecter les captures dans `screenshots` ; rapports dans `.cache/offline-validation`.

La confirmation de chargement au premier lancement protégé reste indispensable. Les contrôles du paquet ne valident pas toutes les versions de lazer, ni l'approbation par l'équipe osu!. Ce fork conserve les identifiants techniques MOsu et n'offre aucune garantie concernant les décisions de modération.

Projet dérivé de [p-720/mosu](https://github.com/p-720/mosu), avec les attributions et licences du dépôt conservées. Tachyon est un canal officiel expérimental d'osu!lazer.
