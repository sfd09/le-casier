-- =====================================================================
--  LE CASIER — schéma de la base
--  À coller tel quel dans Supabase : SQL Editor > New query > Run.
--  Le script est ré-exécutable : il supprime et recrée proprement.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. TABLES
-- ---------------------------------------------------------------------

drop table if exists public.objets  cascade;
drop table if exists public.membres cascade;

create table public.membres (
  id       uuid primary key references auth.users(id) on delete cascade,
  pseudo   text        not null check (char_length(pseudo) between 1 and 20),
  classe   text                 check (char_length(classe) <= 12),
  credits  integer     not null default 2 check (credits >= 0),
  dons     integer     not null default 0 check (dons    >= 0),
  cree_le  timestamptz not null default now()
);

comment on table public.membres is
  'Un élève. Aucune donnée nominative : pseudo et classe seulement.';

create table public.objets (
  id           uuid primary key default gen_random_uuid(),
  proprietaire uuid not null references public.membres(id) on delete cascade,
  preneur      uuid          references public.membres(id) on delete set null,

  titre     text not null check (char_length(titre) between 1 and 90),
  auteur    text          check (char_length(auteur) <= 60),
  isbn      text          check (isbn ~ '^[0-9Xx]{0,17}$'),
  categorie text not null check (categorie in
              ('manuel','lecture','calc','materiel','fournitures','sport','autre')),
  matiere   text,
  niveau    text,
  etat      text,
  note      text          check (char_length(note) <= 200),

  mode   text not null check (mode   in ('don','troc','vente')),
  statut text not null default 'dispo'
                     check (statut in ('dispo','reserve','echange')),

  -- Le plafond est répliqué ici volontairement : le contrôle du
  -- formulaire peut être contourné, celui de la base non.
  prix numeric(6,2) not null default 0 check (prix >= 0 and prix <= 40),

  signale   boolean     not null default false,
  depose_le timestamptz not null default now(),

  -- Une vente doit avoir un prix ; un don et un troc n'en ont pas.
  constraint prix_coherent check (
    (mode = 'vente' and prix > 0) or (mode <> 'vente' and prix = 0)
  )
);

create index objets_statut_idx on public.objets (statut, depose_le desc);
create index objets_proprio_idx on public.objets (proprietaire);

-- ---------------------------------------------------------------------
--  2. SÉCURITÉ AU NIVEAU DES LIGNES
--     Lecture ouverte à tout élève connecté ; aucune écriture directe.
--     Toutes les modifications passent par les fonctions du point 3,
--     qui seules savent tenir les crédits à jour de façon cohérente.
-- ---------------------------------------------------------------------

alter table public.membres enable row level security;
alter table public.objets  enable row level security;

create policy "lecture des membres" on public.membres
  for select to authenticated using (true);

create policy "lecture des annonces" on public.objets
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
--  3. OPÉRATIONS
--     En « security definer » : elles s'exécutent avec les droits du
--     propriétaire du schéma, ce qui leur permet de débiter le crédit
--     d'un élève et d'incréditer le compteur de dons d'un autre — en
--     une seule transaction, donc sans risque d'incohérence.
-- ---------------------------------------------------------------------

create or replace function public.creer_membre(p_pseudo text, p_classe text)
returns public.membres
language plpgsql security definer set search_path = public as $$
declare m public.membres;
begin
  insert into public.membres (id, pseudo, classe)
       values (auth.uid(), trim(p_pseudo), nullif(trim(p_classe), ''))
  on conflict (id) do update
       set pseudo = excluded.pseudo, classe = excluded.classe
  returning * into m;
  return m;
end $$;

create or replace function public.deposer_objet(
  p_titre text, p_auteur text, p_isbn text, p_categorie text,
  p_matiere text, p_niveau text, p_etat text, p_note text,
  p_mode text, p_prix numeric
) returns public.objets
language plpgsql security definer set search_path = public as $$
declare o public.objets;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;

  insert into public.objets (proprietaire, titre, auteur, isbn, categorie,
                             matiere, niveau, etat, note, mode, prix)
       values (auth.uid(), trim(p_titre), nullif(trim(p_auteur),''),
               nullif(trim(p_isbn),''), p_categorie,
               nullif(p_matiere,''), nullif(p_niveau,''), p_etat,
               nullif(trim(p_note),''), p_mode,
               case when p_mode = 'vente' then p_prix else 0 end)
  returning * into o;

  -- Seul le troc alimente les crédits.
  if p_mode = 'troc' then
    update public.membres set credits = credits + 1 where id = auth.uid();
  end if;

  return o;
end $$;

create or replace function public.reserver_objet(p_objet uuid)
returns public.objets
language plpgsql security definer set search_path = public as $$
declare o public.objets; c integer;
begin
  select * into o from public.objets where id = p_objet for update;

  if not found                     then raise exception 'annonce introuvable'; end if;
  if o.statut <> 'dispo'           then raise exception 'annonce déjà réservée'; end if;
  if o.signale                     then raise exception 'annonce signalée'; end if;
  if o.proprietaire = auth.uid()   then raise exception 'annonce déjà à vous'; end if;

  if o.mode = 'troc' then
    select credits into c from public.membres where id = auth.uid() for update;
    if coalesce(c,0) < 1 then raise exception 'crédits insuffisants'; end if;
    update public.membres set credits = credits - 1 where id = auth.uid();
  end if;

  update public.objets set statut = 'reserve', preneur = auth.uid()
   where id = p_objet returning * into o;
  return o;
end $$;

create or replace function public.annuler_reservation(p_objet uuid)
returns public.objets
language plpgsql security definer set search_path = public as $$
declare o public.objets;
begin
  select * into o from public.objets where id = p_objet for update;
  if o.preneur is distinct from auth.uid() then
    raise exception 'ce n''est pas votre réservation';
  end if;

  if o.mode = 'troc' then
    update public.membres set credits = credits + 1 where id = auth.uid();
  end if;

  update public.objets set statut = 'dispo', preneur = null
   where id = p_objet returning * into o;
  return o;
end $$;

create or replace function public.confirmer_echange(p_objet uuid)
returns public.objets
language plpgsql security definer set search_path = public as $$
declare o public.objets;
begin
  select * into o from public.objets where id = p_objet for update;
  if o.preneur is distinct from auth.uid() then
    raise exception 'ce n''est pas votre réservation';
  end if;

  -- Le don ne rapporte pas de crédit : il alimente le compteur de dons.
  if o.mode = 'don' then
    update public.membres set dons = dons + 1 where id = o.proprietaire;
  end if;

  update public.objets set statut = 'echange'
   where id = p_objet returning * into o;
  return o;
end $$;

create or replace function public.retirer_objet(p_objet uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare o public.objets;
begin
  select * into o from public.objets where id = p_objet for update;
  if o.proprietaire is distinct from auth.uid() then
    raise exception 'annonce d''un autre élève';
  end if;

  -- On reprend le crédit gagné au dépôt, sauf si l'échange a eu lieu.
  if o.mode = 'troc' and o.statut <> 'echange' then
    update public.membres set credits = greatest(credits - 1, 0)
     where id = auth.uid();
  end if;

  delete from public.objets where id = p_objet;
end $$;

create or replace function public.signaler_objet(p_objet uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  update public.objets set signale = true where id = p_objet;
end $$;

-- Seuls les élèves connectés peuvent appeler ces opérations.
revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

-- ---------------------------------------------------------------------
--  4. TEMPS RÉEL
--     Le catalogue se met à jour chez tout le monde, sans rechargement.
-- ---------------------------------------------------------------------

alter publication supabase_realtime add table public.objets;
alter publication supabase_realtime add table public.membres;
