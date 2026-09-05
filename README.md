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
