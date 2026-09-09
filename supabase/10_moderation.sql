-- =====================================================================
--  LE CASIER — modération
--  À exécuter APRÈS 09_fiches_detaillees.sql.
-- =====================================================================
--
--  Le signalement d'origine avait trois défauts :
--
--   1. Il était sans retour. `signale = true` ne pouvait jamais revenir
--      à false : une annonce signalée à tort disparaissait pour de bon.
--   2. Il était sans trace ni limite. N'importe quel élève connecté
--      pouvait masquer n'importe quelle annonce, autant de fois qu'il
--      voulait, sans qu'on sache qui ni pourquoi.
--   3. Il n'existait aucun adulte référent dans la base, donc aucune
--      façon de trancher.
--
--  Cette migration ajoute les trois pièces manquantes : des référents,
--  des signalements motivés et traçables, et une décision réversible.

-- ---------------------------------------------------------------------
--  1. LES RÉFÉRENTS
--     Un adulte de l'établissement. On ne s'inscrit pas soi-même :
--     la table ne se remplit que depuis l'éditeur SQL de Supabase
--     (voir la commande en fin de fichier).
-- ---------------------------------------------------------------------

create table if not exists public.referents (
  id      uuid primary key references auth.users(id) on delete cascade,
  nom     text not null check (char_length(nom) between 1 and 60),
  depuis  timestamptz not null default now()
);

comment on table public.referents is
  'Adultes habilités à trancher un signalement. Se remplit à la main.';

alter table public.referents enable row level security;

-- Chacun peut vérifier s'il est lui-même référent, personne ne voit la liste.
drop policy if exists "je vois si je suis référent" on public.referents;
create policy "je vois si je suis référent" on public.referents
  for select to authenticated using (id = auth.uid());

create or replace function public.est_referent()
returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.referents where id = auth.uid());
$$;

-- ---------------------------------------------------------------------
--  2. LES SIGNALEMENTS
--     Une ligne par (annonce, élève) : on ne signale qu'une fois.
-- ---------------------------------------------------------------------

create table if not exists public.signalements (
  id         uuid primary key default gen_random_uuid(),
  objet      uuid not null references public.objets(id)  on delete cascade,
  auteur     uuid not null references public.membres(id) on delete cascade,
  motif      text not null check (motif in
               ('inapproprie','interdit','prix','faux','autre')),
  precisions text check (char_length(precisions) <= 300),
  cree_le    timestamptz not null default now(),
  unique (objet, auteur)
);

create index if not exists signalements_objet_idx on public.signalements (objet);
create index if not exists signalements_auteur_idx on public.signalements (auteur, cree_le desc);

alter table public.signalements enable row level security;

-- Seuls les référents lisent les signalements. Un élève ne doit pas
-- pouvoir savoir qui l'a signalé : c'est ce qui protège le signalant.
drop policy if exists "lecture par les référents" on public.signalements;
create policy "lecture par les référents" on public.signalements
  for select to authenticated using (public.est_referent());

-- ---------------------------------------------------------------------
--  3. L'ÉTAT DE MODÉRATION D'UNE ANNONCE
--
--     libre   : rien à signaler
--     masque  : signalée, retirée de la vue en attendant un adulte
--     valide  : un référent l'a examinée et rétablie. Elle ne peut plus
--               être masquée par un nouveau signalement — sinon un élève
--               décidé recommencerait indéfiniment.
--
--     La colonne `signale` est conservée : tout le code de l'application
--     s'en sert. Elle devient le reflet de `moderation = 'masque'`.
-- ---------------------------------------------------------------------

alter table public.objets add column if not exists moderation text not null default 'libre';

do $$ begin
  alter table public.objets add constraint moderation_connue
    check (moderation in ('libre','masque','valide'));
exception when duplicate_object then null; end $$;

-- Reprise de l'existant : ce qui était signalé devient « masqué ».
update public.objets set moderation = 'masque' where signale and moderation = 'libre';

-- ---------------------------------------------------------------------
--  4. SIGNALER
--     Même nom qu'avant, avec un motif. Les anciens appels à un seul
--     argument continuent de fonctionner.
-- ---------------------------------------------------------------------

-- L'ancienne version rendait « void » et ne prenait qu'un argument.
-- Postgres refuse de changer le type de retour d'une fonction existante,
-- et une signature différente créerait une deuxième fonction à côté de
-- la première : il faut retirer l'ancienne, explicitement.
drop function if exists public.signaler_objet(uuid);

create or replace function public.signaler_objet(
  p_objet      uuid,
  p_motif      text default 'autre',
  p_precisions text default null
) returns text
language plpgsql security definer set search_path = public as $$
declare o public.objets; recents integer;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;

  select * into o from public.objets where id = p_objet for update;
  if not found then raise exception 'annonce introuvable'; end if;
  if o.proprietaire = auth.uid() then
    raise exception 'votre propre annonce';
  end if;

  -- Garde-fou contre le vandalisme : signaler tout le casier d'affilée
  -- n'est pas un usage plausible.
  select count(*) into recents from public.signalements
   where auteur = auth.uid() and cree_le > now() - interval '24 hours';
  if recents >= 5 then raise exception 'trop de signalements'; end if;

  insert into public.signalements (objet, auteur, motif, precisions)
       values (p_objet, auth.uid(), p_motif,
               nullif(trim(coalesce(p_precisions,'')), ''))
  on conflict (objet, auteur) do nothing;

  -- Rien d'inséré : c'est que l'élève avait déjà signalé cette annonce.
  if not found then raise exception 'déjà signalée par vous'; end if;

  -- Une annonce déjà tranchée par un adulte reste visible : le
  -- signalement est enregistré, le référent le verra.
  if o.moderation = 'valide' then
    return 'deja_verifiee';
  end if;

  update public.objets set moderation = 'masque', signale = true
   where id = p_objet;
  return 'masquee';
end $$;

-- ---------------------------------------------------------------------
--  5. TRANCHER
--     Réservé aux référents. Deux issues : rétablir ou retirer.
-- ---------------------------------------------------------------------

create or replace function public.moderer_objet(p_objet uuid, p_decision text)
returns text
language plpgsql security definer set search_path = public as $$
declare o public.objets;
begin
  if not public.est_referent() then raise exception 'réservé au référent'; end if;
  if p_decision not in ('retablir','retirer') then
    raise exception 'décision inconnue';
  end if;

  select * into o from public.objets where id = p_objet for update;
  if not found then raise exception 'annonce introuvable'; end if;

  if p_decision = 'retablir' then
    update public.objets set moderation = 'valide', signale = false
     where id = p_objet;
    return 'retablie';
  end if;

  -- Retrait. Il faut défaire les crédits comme le ferait le propriétaire
  -- en retirant lui-même son annonce, et rendre au preneur ce qu'il a
  -- payé s'il avait réservé — sans quoi la suppression crée ou détruit
  -- des crédits.
  if o.mode = 'troc' then
    if o.statut <> 'echange' then
      update public.membres set credits = greatest(credits - 1, 0)
       where id = o.proprietaire;
    end if;
    if o.statut = 'reserve' and o.preneur is not null then
      update public.membres set credits = credits + 1 where id = o.preneur;
    end if;
  end if;

  delete from public.objets where id = p_objet;
  return 'retiree';
end $$;

-- ---------------------------------------------------------------------
--  6. NE PAS EFFACER LES PIÈCES DU DOSSIER
--     Sans cela, l'élève signalé supprime son annonce avant que
--     l'adulte l'ait vue, et la console ne sert plus à rien.
-- ---------------------------------------------------------------------

create or replace function public.retirer_objet(p_objet uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare o public.objets;
begin
  select * into o from public.objets where id = p_objet for update;
  if o.proprietaire is distinct from auth.uid() then
    raise exception 'annonce d''un autre élève';
  end if;
  if o.moderation = 'masque' then
    raise exception 'annonce en cours de vérification';
  end if;

  -- On reprend le crédit gagné au dépôt, sauf si l'échange a eu lieu.
  if o.mode = 'troc' and o.statut <> 'echange' then
    update public.membres set credits = greatest(credits - 1, 0)
     where id = auth.uid();
  end if;

  delete from public.objets where id = p_objet;
end $$;

-- ---------------------------------------------------------------------
--  7. LA FILE D'ATTENTE DU RÉFÉRENT
--     Une seule requête plutôt qu'une par annonce.
-- ---------------------------------------------------------------------

create or replace function public.file_moderation()
returns table (
  objet        uuid,
  titre        text,
  categorie    text,
  mode         text,
  prix         numeric,
  note         text,
  photo        text,
  statut       text,
  moderation   text,
  proprietaire text,
  classe       text,
  nb           bigint,
  motifs       text[],
  precisions   text[],
  premier      timestamptz
)
language sql security definer set search_path = public stable as $$
  select o.id, o.titre, o.categorie, o.mode, o.prix, o.note, o.photo,
         o.statut, o.moderation,
         m.pseudo, coalesce(m.classe,''),
         count(s.id),
         array_agg(s.motif order by s.cree_le),
         array_remove(array_agg(s.precisions order by s.cree_le), null),
         min(s.cree_le)
    from public.signalements s
    join public.objets  o on o.id = s.objet
    join public.membres m on m.id = o.proprietaire
   where public.est_referent()
   group by o.id, m.pseudo, m.classe
   order by (o.moderation = 'masque') desc, min(s.cree_le);
$$;

-- ---------------------------------------------------------------------
--  8. DROITS
--     Comme au schéma initial : rien pour les visiteurs, tout pour les
--     élèves connectés. Ce sont les fonctions elles-mêmes qui vérifient
--     le rôle de référent.
-- ---------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

-- ---------------------------------------------------------------------
--  DÉSIGNER UN RÉFÉRENT
--
--  L'adulte crée d'abord un compte normal dans l'application, puis on
--  exécute ici, une fois, en remplaçant l'adresse et le nom :
--
--    insert into public.referents (id, nom)
--    select id, 'Mme Untel, CDI' from auth.users
--     where email = 'prenom.nom@monlycee.net'
--    on conflict (id) do nothing;
--
--  Pour lui retirer le rôle :
--
--    delete from public.referents
--     where id = (select id from auth.users where email = '…');
-- ---------------------------------------------------------------------
