-- =====================================================================
--  LE CASIER — mémoire partagée des fiches de livres
--  À exécuter APRÈS 06_vignettes.sql.
-- =====================================================================
--
--  Les catalogues internationaux ignorent l'édition scolaire française.
--  Vérifié : l'ISBN 9782340042384 (Ellipses) est inconnu d'Open Library,
--  et absent de la BnF. Aucune source publique ne le décrit.
--
--  D'où ce renversement : le lycée devient sa propre source. Le premier
--  élève saisit le manuel à la main ; sa fiche est conservée ; tous les
--  suivants qui entrent le même ISBN l'obtiennent aussitôt.
--
--  Trente élèves partagent le même manuel de spécialité : la saisie
--  n'est faite qu'une fois pour toutes.

create table if not exists public.fiches (
  isbn      text primary key check (isbn ~ '^[0-9]{13}$'),
  titre     text not null check (char_length(titre) between 1 and 90),
  auteur    text,
  categorie text,
  matiere   text,
  niveau    text,
  saisies   integer     not null default 1,
  maj       timestamptz not null default now()
);

comment on table public.fiches is
  'Fiches de livres constituées par les élèves eux-mêmes, là où aucun
   catalogue public ne répond. saisies compte les confirmations.';

alter table public.fiches enable row level security;

drop policy if exists "fiches lisibles" on public.fiches;
create policy "fiches lisibles" on public.fiches
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
--  Enregistrement d'une fiche
--  Appelée au dépôt d'une annonce portant un ISBN. Les champs vides ne
--  remplacent jamais un champ déjà renseigné : une saisie partielle ne
--  doit pas appauvrir une fiche complète.
-- ---------------------------------------------------------------------

create or replace function public.enregistrer_fiche(
  p_isbn text, p_titre text, p_auteur text,
  p_categorie text, p_matiere text, p_niveau text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  if p_isbn is null or p_isbn !~ '^[0-9]{13}$' then return; end if;
  if p_titre is null or trim(p_titre) = '' then return; end if;

  insert into public.fiches (isbn, titre, auteur, categorie, matiere, niveau)
       values (p_isbn, trim(p_titre), nullif(trim(coalesce(p_auteur,'')),''),
               nullif(p_categorie,''), nullif(p_matiere,''), nullif(p_niveau,''))
  on conflict (isbn) do update set
       titre     = coalesce(nullif(trim(excluded.titre),''), fiches.titre),
       auteur    = coalesce(excluded.auteur,    fiches.auteur),
       categorie = coalesce(excluded.categorie, fiches.categorie),
       matiere   = coalesce(excluded.matiere,   fiches.matiere),
       niveau    = coalesce(excluded.niveau,    fiches.niveau),
       saisies   = fiches.saisies + 1,
       maj       = now();
end $$;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

select 'table fiches créée' as resultat;
