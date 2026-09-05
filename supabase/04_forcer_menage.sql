-- =====================================================================
--  LE CASIER — supprimer de force le déclencheur défectueux
--  À coller dans l'éditeur SQL. Affiche le résultat à la fin.
-- =====================================================================
--
--  Tant qu'un déclencheur subsiste sur public.objets, toute suppression
--  d'annonce échoue avec :
--      Direct deletion from storage tables is not allowed.
--
--  Ce script retire TOUS les déclencheurs applicatifs de la table (il
--  n'y en a jamais eu qu'un), puis affiche ce qui reste.

do $$
declare t record;
begin
  for t in
    select tgname
      from pg_trigger
     where tgrelid = 'public.objets'::regclass
       and not tgisinternal
  loop
    execute format('drop trigger %I on public.objets', t.tgname);
    raise notice 'déclencheur supprimé : %', t.tgname;
  end loop;
end $$;

drop function if exists public.supprimer_photo_associee() cascade;

-- Résultat : ce tableau doit être VIDE.
select tgname as declencheurs_restants
  from pg_trigger
 where tgrelid = 'public.objets'::regclass
   and not tgisinternal;
