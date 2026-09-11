-- =====================================================================
--  LE CASIER — prévenir quand une annonce répond à une demande
--  À exécuter APRÈS 14_lecture.sql.
-- =====================================================================
--
--  Une demande publiée n'avertissait personne : elle attendait qu'un
--  élève pense à consulter un onglet qu'il n'ouvrait jamais. C'est ce
--  qui condamne ce genre de fonctionnalité.
--
--  Désormais, déposer une annonce cherche les demandes qu'elle satisfait
--  et prévient ceux qui les ont publiées.

create or replace function public.correspondances(p_objet uuid)
returns table (membre uuid, demande text)
language sql security definer set search_path = public stable as $$
  select r.demandeur, r.titre
    from public.recherches r
    join public.objets o on o.id = p_objet
   where r.active
     and r.demandeur <> o.proprietaire          -- on ne s'avertit pas soi-même
     and o.statut = 'dispo'
     and coalesce(o.moderation, 'libre') <> 'masque'
     and (
       -- Un code identique ne laisse aucun doute : même édition, même objet.
       (r.isbn is not null and o.isbn is not null and r.isbn = o.isbn)
       or (
         -- Sinon : même catégorie, et les précisions données doivent
         -- concorder. Une demande sans matière accepte toute matière ;
         -- ne rien exiger d'absent évite de rater par excès de zèle.
         r.categorie is not null
         and r.categorie = o.categorie
         and (r.matiere is null or o.matiere is null or r.matiere = o.matiere)
         and (r.niveau  is null or o.niveau  is null or r.niveau  = o.niveau)
       )
     )
   group by r.demandeur, r.titre;
$$;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

-- ---------------------------------------------------------------------
--  Déclencheur : à chaque dépôt, on interroge la fonction d'envoi.
-- ---------------------------------------------------------------------

create or replace function public.prevenir_correspondances()
returns trigger
language plpgsql security definer set search_path = public, extensions, net as $$
begin
  perform net.http_post(
    url := 'https://nprzhyvsxmuyihrqmahe.supabase.co/functions/v1/notifier',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wcnpoeXZzeG11eWlocnFtYWhlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg2MTM2NTAsImV4cCI6MjEwNDE4OTY1MH0.6mIax2bPIl39It0uNRfCxYMyOkLKbWFmfALbuJGgBKQ'
    ),
    body := jsonb_build_object('table', 'objets', 'record', jsonb_build_object('id', new.id)),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  return new;   -- un dépôt ne doit jamais échouer faute de notification
end $$;

drop trigger if exists objets_prevenir on public.objets;
create trigger objets_prevenir
  after insert on public.objets
  for each row execute function public.prevenir_correspondances();

select tgname as declencheurs
  from pg_trigger
 where tgrelid in ('public.objets'::regclass, 'public.messages'::regclass)
   and not tgisinternal;
