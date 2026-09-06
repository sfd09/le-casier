-- =====================================================================
--  LE CASIER — demandes et fils de discussion
--  À exécuter APRÈS 07_fiches.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. LES DEMANDES
--     Le catalogue ne montre que ce que les élèves possèdent. Afficher
--     aussi ce qu'ils cherchent amorce l'offre : personne ne pense à
--     sortir son vieux manuel de SES, mais on le sort quand on voit que
--     trois personnes le réclament.
-- ---------------------------------------------------------------------

create table if not exists public.recherches (
  id        uuid primary key default gen_random_uuid(),
  demandeur uuid not null references public.membres(id) on delete cascade,
  titre     text not null check (char_length(titre) between 1 and 90),
  isbn      text check (isbn ~ '^[0-9]{13}$'),
  categorie text check (categorie in
              ('manuel','lecture','calc','materiel','fournitures','sport','autre')),
  matiere   text,
  niveau    text,
  note      text check (char_length(note) <= 200),
  active    boolean     not null default true,
  cree_le   timestamptz not null default now()
);

create index if not exists recherches_actives_idx on public.recherches (active, cree_le desc);

alter table public.recherches enable row level security;
drop policy if exists "recherches lisibles" on public.recherches;
create policy "recherches lisibles" on public.recherches
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
--  2. LES FILS DE DISCUSSION
--     Un fil par (annonce, personne intéressée). Le propriétaire et
--     l'intéressé sont les deux seuls à le voir : les tractations sur un
--     rendez-vous ne regardent pas le reste du lycée.
-- ---------------------------------------------------------------------

create table if not exists public.fils (
  id           uuid primary key default gen_random_uuid(),
  objet        uuid not null references public.objets(id)  on delete cascade,
  proprietaire uuid not null references public.membres(id) on delete cascade,
  demandeur    uuid not null references public.membres(id) on delete cascade,
  cree_le      timestamptz not null default now(),
  maj          timestamptz not null default now(),
  unique (objet, demandeur)
);

create index if not exists fils_maj_idx on public.fils (maj desc);

create table if not exists public.messages (
  id        uuid primary key default gen_random_uuid(),
  fil       uuid not null references public.fils(id) on delete cascade,
  auteur    uuid not null references public.membres(id) on delete cascade,
  texte     text not null check (char_length(texte) between 1 and 800),
  envoye_le timestamptz not null default now()
);

create index if not exists messages_fil_idx on public.messages (fil, envoye_le);

alter table public.fils     enable row level security;
alter table public.messages enable row level security;

-- Seuls les deux participants voient le fil et ses messages.
drop policy if exists "mes fils" on public.fils;
create policy "mes fils" on public.fils
  for select to authenticated
  using (proprietaire = auth.uid() or demandeur = auth.uid());

drop policy if exists "mes messages" on public.messages;
create policy "mes messages" on public.messages
  for select to authenticated
  using (exists (
    select 1 from public.fils f
     where f.id = messages.fil
       and (f.proprietaire = auth.uid() or f.demandeur = auth.uid())
  ));

-- ---------------------------------------------------------------------
--  3. OPÉRATIONS
-- ---------------------------------------------------------------------

create or replace function public.publier_recherche(
  p_titre text, p_isbn text, p_categorie text,
  p_matiere text, p_niveau text, p_note text
) returns public.recherches
language plpgsql security definer set search_path = public as $$
declare r public.recherches;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  insert into public.recherches (demandeur, titre, isbn, categorie, matiere, niveau, note)
       values (auth.uid(), trim(p_titre), nullif(p_isbn,''), nullif(p_categorie,''),
               nullif(p_matiere,''), nullif(p_niveau,''), nullif(trim(coalesce(p_note,'')),''))
  returning * into r;
  return r;
end $$;

create or replace function public.retirer_recherche(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.recherches where id = p_id and demandeur = auth.uid();
end $$;

-- Ouvre le fil avec le propriétaire de l'annonce, ou rend celui qui
-- existe déjà. Un seul fil par annonce et par personne intéressée.
create or replace function public.ouvrir_fil(p_objet uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.objets; f uuid;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  select * into o from public.objets where id = p_objet;
  if not found then raise exception 'annonce introuvable'; end if;
  if o.proprietaire = auth.uid() then raise exception 'annonce déjà à vous'; end if;

  select id into f from public.fils where objet = p_objet and demandeur = auth.uid();
  if f is not null then return f; end if;

  insert into public.fils (objet, proprietaire, demandeur)
       values (p_objet, o.proprietaire, auth.uid())
  returning id into f;
  return f;
end $$;

create or replace function public.envoyer_message(p_fil uuid, p_texte text)
returns public.messages
language plpgsql security definer set search_path = public as $$
declare f public.fils; m public.messages;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  select * into f from public.fils where id = p_fil;
  if not found then raise exception 'fil introuvable'; end if;
  if f.proprietaire <> auth.uid() and f.demandeur <> auth.uid() then
    raise exception 'fil d''autres élèves';
  end if;
  if trim(coalesce(p_texte,'')) = '' then raise exception 'message vide'; end if;

  insert into public.messages (fil, auteur, texte)
       values (p_fil, auth.uid(), trim(p_texte))
  returning * into m;
  update public.fils set maj = now() where id = p_fil;
  return m;
end $$;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.recherches;

select 'recherches, fils et messages créés' as resultat;
