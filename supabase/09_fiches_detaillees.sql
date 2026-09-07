-- =====================================================================
--  LE CASIER — fiches de livres enrichies
--  À exécuter APRÈS 08_recherches_messages.sql.
-- =====================================================================
--
--  Les catalogues donnent bien plus que le titre et l'auteur. Le SUDOC
--  fournit pour un manuel : l'éditeur, l'année, la pagination, un résumé
--  et les sujets traités. Les stocker une fois par ISBN évite de les
--  redemander à chaque annonce, et profite à tous les élèves.

alter table public.fiches add column if not exists editeur    text;
alter table public.fiches add column if not exists annee      integer;
alter table public.fiches add column if not exists pages      integer;
alter table public.fiches add column if not exists resume     text;
alter table public.fiches add column if not exists couverture text;

comment on column public.fiches.resume is
  'Résumé fourni par le catalogue. Renseigné automatiquement, jamais saisi.';

drop function if exists public.enregistrer_fiche(text,text,text,text,text,text);

create or replace function public.enregistrer_fiche(
  p_isbn text, p_titre text, p_auteur text,
  p_categorie text, p_matiere text, p_niveau text,
  p_editeur text default null, p_annee integer default null,
  p_pages integer default null, p_resume text default null,
  p_couverture text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  if p_isbn is null or p_isbn !~ '^[0-9]{13}$' then return; end if;
  if p_titre is null or trim(p_titre) = '' then return; end if;

  insert into public.fiches (isbn, titre, auteur, categorie, matiere, niveau,
                             editeur, annee, pages, resume, couverture)
       values (p_isbn, trim(p_titre), nullif(trim(coalesce(p_auteur,'')),''),
               nullif(p_categorie,''), nullif(p_matiere,''), nullif(p_niveau,''),
               nullif(trim(coalesce(p_editeur,'')),''), p_annee, p_pages,
               nullif(trim(coalesce(p_resume,'')),''),
               nullif(trim(coalesce(p_couverture,'')),''))
  on conflict (isbn) do update set
       -- une saisie partielle n'appauvrit jamais une fiche complète
       titre      = coalesce(nullif(trim(excluded.titre),''), fiches.titre),
       auteur     = coalesce(excluded.auteur,     fiches.auteur),
       categorie  = coalesce(excluded.categorie,  fiches.categorie),
       matiere    = coalesce(excluded.matiere,    fiches.matiere),
       niveau     = coalesce(excluded.niveau,     fiches.niveau),
       editeur    = coalesce(excluded.editeur,    fiches.editeur),
       annee      = coalesce(excluded.annee,      fiches.annee),
       pages      = coalesce(excluded.pages,      fiches.pages),
       resume     = coalesce(excluded.resume,     fiches.resume),
       couverture = coalesce(excluded.couverture, fiches.couverture),
       saisies    = fiches.saisies + 1,
       maj        = now();
end $$;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

select 'fiches enrichies' as resultat;
