# Le Casier — prototype local

## Lancer

Double-cliquez sur `index.html`. Il s'ouvre dans votre navigateur, rien à installer.

Si les accents s'affichent mal ou si vos annonces ne sont pas conservées d'une
fois sur l'autre, passez par un petit serveur local — c'est la méthode fiable :

    cd ~/Documents/le-casier
    python3 -m http.server 8000

Puis ouvrez http://localhost:8000 dans le navigateur.
Pour arrêter le serveur : Ctrl+C dans le Terminal.

## Modifier

Ouvrez `index.html` dans un éditeur de code (VS Code, gratuit).
N'utilisez pas TextEdit : il enregistre en texte enrichi et casse le fichier.

Après chaque modification : enregistrez, puis rechargez la page (Cmd+R).

Quelques repères dans le fichier :

  PLAFOND_PRIX      le plafond des ventes, en euros
  CATEGORIES        les sept catégories d'objets
  MATIERES          la liste des matières
  EXEMPLES          le catalogue de démonstration
  :root { ... }     toutes les couleurs, en haut du fichier

## Remettre la démo à zéro

Vos annonces sont stockées dans le navigateur. Pour repartir du catalogue
d'exemples (utile avant de montrer le projet à quelqu'un) :

  Chrome / Edge   Cmd+Option+I, onglet Console, tapez  localStorage.clear()
                  puis rechargez la page
  Safari          Réglages > Confidentialité > Gérer les données de sites web

## Version en ligne

https://claude.ai/code/artifact/96721c70-fead-4f7d-a1b7-e257202d277b

C'est ce lien qu'on partage. Le fichier local sert à bricoler.

## Installation sur téléphone

L'application est une PWA : elle s'installe sur l'écran d'accueil sans
passer par l'App Store ni le Play Store.

  iPhone / iPad   Ouvrir le lien dans Safari (pas Chrome), bouton Partager,
                  « Sur l'écran d'accueil »
  Android         Ouvrir dans Chrome, menu ..., « Installer l'application »

Une fois installée, elle s'ouvre en plein écran, sans barre de navigateur,
et fonctionne hors ligne.

## Structure des fichiers

  index.html              l'application entière (source de référence)
  manifest.webmanifest    nom, icônes et couleurs de l'app installée
  sw.js                   service worker : hors ligne + installation
  icones/                 icônes 192, 512 et Apple
  .nojekyll               désactive Jekyll sur GitHub Pages

## Base de données (Supabase)

Le catalogue est partagé : hébergé sur Supabase, région Europe.

  supabase/schema.sql   tables, sécurité et opérations — à coller dans
                        l'éditeur SQL de Supabase pour recréer la base

Principe : les tables sont en LECTURE SEULE pour les élèves. Toute
modification passe par une des fonctions SQL du schéma, qui s'exécutent
en une seule transaction. C'est ce qui garantit qu'un crédit ne peut être
ni créé ni perdu quand deux élèves agissent en même temps.

L'identification est anonyme : chaque appareil reçoit un identifiant
stable, sans e-mail ni mot de passe.

La clé `anon` présente dans index.html est publique par conception : ce
sont les règles du schéma qui protègent les données, pas le secret de
cette clé. La clé `service_role`, elle, ne doit JAMAIS figurer dans ce
dépôt.

### Repartir de zéro pour une démonstration

Dans la console du navigateur :

    localStorage.clear(); location.reload()

Vous obtenez une nouvelle identité anonyme et l'application redemande un
pseudo. Le catalogue, lui, reste partagé : c'est le principe.
