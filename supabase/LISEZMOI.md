# Migrations de la base

À exécuter **dans l'ordre des numéros**, dans l'éditeur SQL de Supabase.

  01_schema.sql    tables, sécurité, opérations
  02_photos.sql    stockage des photos

## Pourquoi des fichiers séparés

`01_schema.sql` commence par `drop table ... cascade` : il RECRÉE la base
à zéro et **efface toutes les annonces**. Il ne se relance que pour
repartir d'une base vierge.

Les fichiers suivants sont des ajouts à une base existante : ils ne
détruisent rien et peuvent se relancer sans dommage.

Conséquence : si vous relancez un jour `01_schema.sql`, il faut relancer
`02_photos.sql` derrière, sinon la colonne photo disparaît.

Tout nouveau changement va dans un NOUVEAU fichier numéroté
(`03_...`), jamais dans un fichier déjà exécuté — sinon on ne sait plus
ce qui a réellement été appliqué à la base.
