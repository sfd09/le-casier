-- =====================================================================
--  LE CASIER — trace de lecture des conversations
--  À exécuter APRÈS 13_declencheur_push.sql.
-- =====================================================================
--
--  La pastille comptait comme « non lu » tout fil dont le dernier
--  message n'était pas de soi. Lire ne l'effaçait donc pas : il fallait
--  répondre. On enregistre désormais le moment où chacun a ouvert la
--  conversation.
--
--  Deux colonnes plutôt qu'une table : un fil n'a que deux participants,
--  et la lecture de l'un ne regarde pas l'autre.

alter table public.fils add column if not exists lu_proprietaire timestamptz;
alter table public.fils add column if not exists lu_demandeur    timestamptz;

comment on column public.fils.lu_proprietaire is
  'Dernière ouverture de la conversation par le propriétaire de l''annonce.';

create or replace function public.marquer_lu(p_fil uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare f public.fils;
begin
  if auth.uid() is null then return; end if;
  select * into f from public.fils where id = p_fil;
  if not found then return; end if;

  if f.proprietaire = auth.uid() then
    update public.fils set lu_proprietaire = now() where id = p_fil;
  elsif f.demandeur = auth.uid() then
    update public.fils set lu_demandeur = now() where id = p_fil;
  end if;
  -- Un tiers ne marque rien : ni erreur, ni effet.
end $$;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

select 'trace de lecture ajoutée' as resultat;
