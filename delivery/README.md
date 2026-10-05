# Paquet Windows

`MOsuOffline-Windows.zip` contient la DLL compilée, le gestionnaire français, son reçu de validation et le guide. Extraire tout le paquet hors de `rulesets` et lire `GUIDE.md`. Aucune installation manuelle de la DLL.

Les contrôles automatisés et la sonde de pare-feu sont validés ; le chargement par le client officiel installé reste **non validé**. Voir [le rapport](../manager/VALIDATION.md).

Reconstruction : `manager/Validate-Package.ps1`, puis `manager/Build-Bundle.ps1`. L'archive générée se trouve dans `artifacts` ; la copie publiée ici correspond à la livraison initiale du fork.
