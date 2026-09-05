-- =====================================================================
--  LE CASIER — vignettes
--  À exécuter APRÈS 05_comptes.sql.
-- =====================================================================
--
--  Le catalogue affichait l'image pleine (1200 px) dans des cases de
--  230 px : six fois trop de données transportées à chaque consultation.
--  Estimation pour 300 élèves actifs consultant 100 annonces par mois :
--  4,5 Go sur les 5 Go inclus dans l'offre gratuite. Sans marge.
--
--  On stocke désormais deux images : une vignette recadrée en 4/3 pour
--  la grille, et l'image pleine pour l'agrandissement au clic.

alter table public.objets add column if not exists photo_min text;

comment on column public.objets.photo_min is
  'Vignette 4/3 affichée dans le catalogue. NULL pour les annonces
   antérieures : l''affichage retombe alors sur photo.';

-- ---------------------------------------------------------------------
--  Le dépôt accepte la seconde image
-- ---------------------------------------------------------------------

drop function if exists public.deposer_objet(text,text,text,text,text,text,text,text,text,numeric,text);

create or replace function public.deposer_objet(
  p_titre text, p_auteur text, p_isbn text, p_categorie text,
  p_matiere text, p_niveau text, p_etat text, p_note text,
  p_mode text, p_prix numeric,
  p_photo text default null, p_photo_min text default null
) returns public.objets
language plpgsql security definer set search_path = public as $$
declare o public.objets;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;

  -- Les deux images doivent être dans le dossier de l'élève.
  if p_photo is not null and split_part(p_photo, '/', 1) <> auth.uid()::text then
    raise exception 'photo d''un autre élève';
  end if;
  if p_photo_min is not null and split_part(p_photo_min, '/', 1) <> auth.uid()::text then
    raise exception 'photo d''un autre élève';
  end if;

  insert into public.objets (proprietaire, titre, auteur, isbn, categorie,
                             matiere, niveau, etat, note, mode, prix,
                             photo, photo_min)
       values (auth.uid(), trim(p_titre), nullif(trim(p_auteur),''),
               nullif(trim(p_isbn),''), p_categorie,
               nullif(p_matiere,''), nullif(p_niveau,''), p_etat,
               nullif(trim(p_note),''), p_mode,
               case when p_mode = 'vente' then p_prix else 0 end,
               nullif(p_photo,''), nullif(p_photo_min,''))
  returning * into o;

  if p_mode = 'troc' then
    update public.membres set credits = credits + 1 where id = auth.uid();
  end if;

  return o;
end $$;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

select 'photo_min ajoutée, deposer_objet mis à jour' as resultat;
