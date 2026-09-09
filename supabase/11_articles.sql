-- =====================================================================
--  LE CASIER — la mémoire du lycée s'étend à tous les articles
--  À exécuter APRÈS 10_moderation.sql.
-- =====================================================================
--
--  `fiches` n'acceptait que des ISBN à 13 chiffres. Or le scanner lit
--  déjà n'importe quel code-barres : c'était l'application qui jetait
--  les autres, faute de savoir quoi en faire.
--
--  Aucune base publique et gratuite ne décrit les objets ordinaires —
--  celles qui le font sont payantes et exigent une clé secrète, qu'une
--  page statique ne peut pas garder. On applique donc aux calculatrices
--  et aux fournitures ce que 07_fiches.sql avait déjà tranché pour les
--  manuels : le lycée est sa propre source. Trente élèves ont la même
--  calculatrice ; sa description n'est saisie qu'une fois.

-- ---------------------------------------------------------------------
--  1. LA COLONNE N'EST PLUS UN ISBN
-- ---------------------------------------------------------------------

do $$ begin
  alter table public.fiches rename column isbn to code;
exception when undefined_column then null; end $$;

-- Les contraintes de vérification sont recréées plus bas : celle sur
-- l'ISBN porte un nom engendré par Postgres, qu'on ne peut pas deviner.
do $$
declare c text;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.fiches'::regclass and contype = 'c'
  loop
    execute format('alter table public.fiches drop constraint %I', c);
  end loop;
end $$;

alter table public.fiches
  add constraint fiches_code_valide check (code ~ '^[0-9]{8}$' or code ~ '^[0-9]{13}$'),
  add constraint fiches_titre_valide check (char_length(titre) between 1 and 90);

comment on table public.fiches is
  'Fiches d''articles constituées par les élèves eux-mêmes : livres par
   leur ISBN, tout le reste par son code-barres. saisies compte les
   dépôts portant ce code.';

comment on column public.fiches.code is
  'EAN-13 (ISBN compris), ou EAN-8. Un UPC-A à 12 chiffres est ramené à
   13 par l''application, en lui rendant le zéro que la norme sous-entend.';

-- ---------------------------------------------------------------------
--  2. LE PREMIER FAIT FOI
--
--     Une fiche est vue par tout le lycée. Laisser chaque déposant
--     réécrire le titre du précédent donnerait à n'importe quel élève
--     le pouvoir de renommer un article pour tous les suivants, autant
--     de fois qu'il le voudrait.
--
--     Donc : le titre du premier est définitif, et les dépôts suivants
--     ne peuvent que **compléter les champs restés vides**. Une fiche
--     s'enrichit, elle ne se réécrit pas. Le référent tranche le reste.
-- ---------------------------------------------------------------------

drop function if exists public.enregistrer_fiche(
  text, text, text, text, text, text, text, integer, integer, text, text);

create or replace function public.enregistrer_fiche(
  p_code text, p_titre text, p_auteur text,
  p_categorie text, p_matiere text, p_niveau text,
  p_editeur text default null, p_annee integer default null,
  p_pages integer default null, p_resume text default null,
  p_couverture text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  if p_code is null or p_code !~ '^([0-9]{8}|[0-9]{13})$' then return; end if;
  if p_titre is null or trim(p_titre) = '' then return; end if;

  insert into public.fiches (code, titre, auteur, categorie, matiere, niveau,
                             editeur, annee, pages, resume, couverture)
       values (p_code, trim(p_titre), nullif(trim(coalesce(p_auteur,'')),''),
               nullif(p_categorie,''), nullif(p_matiere,''), nullif(p_niveau,''),
               nullif(trim(coalesce(p_editeur,'')),''), p_annee, p_pages,
               nullif(trim(coalesce(p_resume,'')),''),
               nullif(trim(coalesce(p_couverture,'')),''))
  on conflict (code) do update set
       -- `titre` est absent : il n'est jamais réécrit.
       auteur     = coalesce(fiches.auteur,     excluded.auteur),
       categorie  = coalesce(fiches.categorie,  excluded.categorie),
       matiere    = coalesce(fiches.matiere,    excluded.matiere),
       niveau     = coalesce(fiches.niveau,     excluded.niveau),
       editeur    = coalesce(fiches.editeur,    excluded.editeur),
       annee      = coalesce(fiches.annee,      excluded.annee),
       pages      = coalesce(fiches.pages,      excluded.pages),
       resume     = coalesce(fiches.resume,     excluded.resume),
       couverture = coalesce(fiches.couverture, excluded.couverture),
       saisies    = fiches.saisies + 1,
       maj        = now();
end $$;

-- ---------------------------------------------------------------------
--  3. LA CORRECTION APPARTIENT AU RÉFÉRENT
--
--     Puisqu'un élève ne peut plus corriger le titre d'un autre, il
--     faut bien que quelqu'un le puisse : sans cela une fiche fautive
--     serait éternelle. Supprimer suffit — le dépôt suivant la recrée.
-- ---------------------------------------------------------------------

create or replace function public.supprimer_fiche(p_code text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.est_referent() then raise exception 'réservé au référent'; end if;
  delete from public.fiches where code = p_code;
end $$;

create or replace function public.fiches_recentes()
returns table (
  code text, titre text, auteur text, categorie text,
  matiere text, niveau text, saisies integer, maj timestamptz
)
language sql security definer set search_path = public stable as $$
  select f.code, f.titre, f.auteur, f.categorie, f.matiere, f.niveau,
         f.saisies, f.maj
    from public.fiches f
   where public.est_referent()
   order by f.maj desc
   limit 60;
$$;

-- ---------------------------------------------------------------------
--  4. DROITS
-- ---------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

select count(*) as fiches_conservees from public.fiches;
