-- =====================================================================
--  LE CASIER — notifications push
--  À exécuter APRÈS 11_articles.sql.
-- =====================================================================
--
--  Un élève qui a écrit à un vendeur ne va pas rouvrir l'application
--  toutes les heures pour voir si on lui a répondu. Sans notification,
--  une négociation s'étale sur trois jours et meurt.
--
--  Le navigateur donne à chaque appareil une adresse d'expédition
--  (endpoint) et deux clés de chiffrement. On les conserve ; l'envoi
--  lui-même est fait par une fonction serveur, seule détentrice de la
--  clé privée VAPID.

create table if not exists public.abonnements_push (
  id        uuid primary key default gen_random_uuid(),
  membre    uuid not null references public.membres(id) on delete cascade,
  endpoint  text not null unique,
  p256dh    text not null,
  auth      text not null,
  appareil  text,
  cree_le   timestamptz not null default now(),
  echecs    integer not null default 0
);

create index if not exists abonnements_membre_idx on public.abonnements_push (membre);

comment on table public.abonnements_push is
  'Un abonnement par appareil. L''endpoint est fourni par le navigateur ;
   il ne permet pas de remonter à la personne, et n''est lisible que
   par son propriétaire.';

alter table public.abonnements_push enable row level security;

-- Personne ne voit les abonnements des autres : un endpoint est une
-- adresse d'expédition, et sa fuite permettrait d'écrire à quelqu'un.
drop policy if exists "mes abonnements" on public.abonnements_push;
create policy "mes abonnements" on public.abonnements_push
  for select to authenticated using (membre = auth.uid());

-- ---------------------------------------------------------------------
--  Enregistrer / retirer un appareil
-- ---------------------------------------------------------------------

create or replace function public.enregistrer_push(
  p_endpoint text, p_p256dh text, p_auth text, p_appareil text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  if p_endpoint is null or p_endpoint = '' then raise exception 'abonnement vide'; end if;

  insert into public.abonnements_push (membre, endpoint, p256dh, auth, appareil)
       values (auth.uid(), p_endpoint, p_p256dh, p_auth, left(coalesce(p_appareil,''), 80))
  -- Un même appareil peut changer de main : l'abonnement suit le compte
  -- actuellement connecté, et le compteur d'échecs repart à zéro.
  on conflict (endpoint) do update set
       membre = auth.uid(), p256dh = excluded.p256dh,
       auth = excluded.auth, echecs = 0;
end $$;

create or replace function public.retirer_push(p_endpoint text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.abonnements_push
   where endpoint = p_endpoint and membre = auth.uid();
end $$;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

select 'abonnements_push créée' as resultat;
