-- =====================================================================
--  LE CASIER — ajout des photos
--  À coller dans Supabase : SQL Editor > New query > Run.
--  À exécuter APRÈS schema.sql. Ré-exécutable sans dommage.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. LA COLONNE
--     On stocke le chemin du fichier, pas l'image : « <identifiant>/<uuid>.jpg »
-- ---------------------------------------------------------------------

alter table public.objets add column if not exists photo text;

-- ---------------------------------------------------------------------
--  2. L'ESPACE DE STOCKAGE
--     Public en lecture : une photo d'objet n'a rien de confidentiel, et
--     les liens signés compliqueraient l'affichage pour rien.
--     2 Mo par fichier : le navigateur compresse déjà avant l'envoi, cette
--     limite n'est qu'un garde-fou contre un contournement.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 2097152, array['image/jpeg','image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = 2097152,
      allowed_mime_types = array['image/jpeg','image/webp'];

-- ---------------------------------------------------------------------
--  3. QUI PEUT FAIRE QUOI
--     Chaque élève écrit uniquement dans le dossier à son nom.
-- ---------------------------------------------------------------------

drop policy if exists "photos lisibles par tous"      on storage.objects;
drop policy if exists "photos deposees chez soi"      on storage.objects;
drop policy if exists "photos supprimables par soi"   on storage.objects;

create policy "photos lisibles par tous" on storage.objects
  for select using (bucket_id = 'photos');

create policy "photos deposees chez soi" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "photos supprimables par soi" on storage.objects
  for delete to authenticated using (
    bucket_id = 'photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------
--  4. MÉNAGE DES PHOTOS
--     Une première version posait ici un déclencheur SQL supprimant la
--     photo avec l'annonce. C'était une erreur : Supabase interdit la
--     suppression directe dans storage.objects depuis du SQL et lève une
--     exception, ce qui annulait le retrait de l'annonce elle-même.
--     Voir 03_menage_photos.sql. Le ménage se fait côté navigateur.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
--  5. LE DÉPÔT ACCEPTE UNE PHOTO
--     On supprime l'ancienne version avant de recréer : ajouter un
--     paramètre créerait sinon une seconde fonction en parallèle.
-- ---------------------------------------------------------------------

drop function if exists public.deposer_objet(text,text,text,text,text,text,text,text,text,numeric);

create or replace function public.deposer_objet(
  p_titre text, p_auteur text, p_isbn text, p_categorie text,
  p_matiere text, p_niveau text, p_etat text, p_note text,
  p_mode text, p_prix numeric, p_photo text default null
) returns public.objets
language plpgsql security definer set search_path = public as $$
declare o public.objets;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;

  -- Une photo ne peut être revendiquée que si elle est dans son dossier.
  if p_photo is not null and split_part(p_photo, '/', 1) <> auth.uid()::text then
    raise exception 'photo d''un autre élève';
  end if;

  insert into public.objets (proprietaire, titre, auteur, isbn, categorie,
                             matiere, niveau, etat, note, mode, prix, photo)
       values (auth.uid(), trim(p_titre), nullif(trim(p_auteur),''),
               nullif(trim(p_isbn),''), p_categorie,
               nullif(p_matiere,''), nullif(p_niveau,''), p_etat,
               nullif(trim(p_note),''), p_mode,
               case when p_mode = 'vente' then p_prix else 0 end,
               nullif(p_photo,''))
  returning * into o;

  if p_mode = 'troc' then
    update public.membres set credits = credits + 1 where id = auth.uid();
  end if;

  return o;
end $$;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;
