-- =====================================================================
--  LE CASIER — comptes réservés aux élèves du lycée
--  À exécuter APRÈS 04_forcer_menage.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. LES DOMAINES ACCEPTÉS
--     Une table plutôt qu'une liste écrite en dur : ajouter un domaine
--     se fait depuis Table Editor, sans toucher au code.
-- ---------------------------------------------------------------------

create table if not exists public.domaines_autorises (
  domaine text primary key,
  note    text
);

insert into public.domaines_autorises (domaine, note) values
  ('monlycee.net', 'ENT des lycées d''Île-de-France')
on conflict (domaine) do nothing;

alter table public.domaines_autorises enable row level security;

-- Lisible pour que l'application puisse afficher « utilisez votre
-- adresse @monlycee.net ». Modifiable uniquement depuis l'éditeur SQL.
drop policy if exists "domaines lisibles" on public.domaines_autorises;
create policy "domaines lisibles" on public.domaines_autorises
  for select to authenticated, anon using (true);

-- ---------------------------------------------------------------------
--  2. LE CONTRÔLE
--     Posé sur la table des comptes, pas dans le formulaire : un
--     contrôle côté navigateur se retire en dix secondes avec les
--     outils de développement. Celui-ci ne se contourne pas.
-- ---------------------------------------------------------------------

create or replace function public.verifier_domaine_eleve()
returns trigger
language plpgsql security definer set search_path = public as $$
declare d text;
begin
  -- Les sessions anonymes n'ont pas d'adresse : on les laisse passer,
  -- c'est ce qui permet de consulter le catalogue avant de s'inscrire.
  if new.email is null or new.email = '' then
    return new;
  end if;

  -- À la modification, on ne contrôle que si l'adresse change vraiment.
  if tg_op = 'UPDATE' and old.email is not distinct from new.email then
    return new;
  end if;

  d := lower(split_part(new.email, '@', 2));

  if not exists (select 1 from public.domaines_autorises where domaine = d) then
    raise exception
      'Inscription réservée aux élèves du lycée : utilisez votre adresse @%',
      (select string_agg(domaine, ' ou @' order by domaine) from public.domaines_autorises);
  end if;

  return new;
end $$;

drop trigger if exists verifier_domaine on auth.users;
create trigger verifier_domaine
  before insert or update of email on auth.users
  for each row execute function public.verifier_domaine_eleve();

-- ---------------------------------------------------------------------
--  3. VÉRIFICATION
--     Doit afficher une ligne : monlycee.net
-- ---------------------------------------------------------------------

select domaine, note from public.domaines_autorises;
