-- =====================================================================
--  LE CASIER — retrait du déclencheur de ménage des photos
--  À exécuter APRÈS 02_photos.sql. Indispensable.
-- =====================================================================
--
--  Le déclencheur posé en 02 est non seulement inutile, il CASSE le
--  retrait des annonces.
--
--  Supabase interdit la suppression directe dans storage.objects depuis
--  du SQL et lève l'exception :
--
--      Direct deletion from storage tables is not allowed.
--      Use the Storage API instead.
--
--  Comme le déclencheur s'exécute AVANT la suppression, cette exception
--  annule toute la transaction : retirer_objet échoue systématiquement
--  dès qu'une annonce porte une photo.
--
--  Le stockage ne se manipule que par son API. La suppression se fait
--  donc depuis le navigateur, juste avant le retrait de l'annonce : le
--  client y est authentifié comme propriétaire, et la politique
--  « photos supprimables par soi » de 02_photos.sql s'applique.

drop trigger  if exists objets_menage_photo         on public.objets;
drop function if exists public.supprimer_photo_associee();
