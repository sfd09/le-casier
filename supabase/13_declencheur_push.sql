-- =====================================================================
--  LE CASIER — déclencher l'envoi des notifications
--  À exécuter APRÈS 12_notifications.sql.
--  Équivaut au « Database Webhook » de l'interface, qui n'est qu'un
--  déclencheur SQL sous un autre nom.
-- =====================================================================

create extension if not exists pg_net with schema extensions;

create or replace function public.prevenir_nouveau_message()
returns trigger
language plpgsql security definer set search_path = public, extensions, net as $$
begin
  -- On ne transmet que l'identifiant : la fonction relit le message
  -- elle-même. Elle est joignable avec la clé publique, donc rien de ce
  -- qui vient d'un appelant ne doit être cru sur parole.
  perform net.http_post(
    url := 'https://nprzhyvsxmuyihrqmahe.supabase.co/functions/v1/notifier',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wcnpoeXZzeG11eWlocnFtYWhlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg2MTM2NTAsImV4cCI6MjEwNDE4OTY1MH0.6mIax2bPIl39It0uNRfCxYMyOkLKbWFmfALbuJGgBKQ'
    ),
    body := jsonb_build_object('record', jsonb_build_object('id', new.id)),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  -- Une notification qui échoue ne doit jamais empêcher l'envoi du
  -- message : l'élève verra sa réponse partir, même si le téléphone
  -- d'en face ne sonne pas.
  return new;
end $$;

drop trigger if exists messages_prevenir on public.messages;
create trigger messages_prevenir
  after insert on public.messages
  for each row execute function public.prevenir_nouveau_message();

-- ---------------------------------------------------------------------
--  Vérification : le déclencheur doit apparaître ici.
-- ---------------------------------------------------------------------
select tgname as declencheur
  from pg_trigger
 where tgrelid = 'public.messages'::regclass
   and not tgisinternal;
