-- =====================================================================
--  LE CASIER — retirer une demande une fois satisfaite
--  À exécuter APRÈS 15_correspondances.sql.
-- =====================================================================
--
--  Rien ne retirait une demande quand l'élève avait fini par obtenir
--  l'objet. Elle continuait de le faire prévenir à chaque dépôt
--  semblable : les alertes devenaient du bruit, et le catalogue
--  affichait des manques comblés depuis longtemps.
--
--  Le moment retenu est la confirmation de l'échange, pas la
--  réservation : réserver n'est qu'une intention, et une réservation
--  annulée doit laisser la demande vivante.

create or replace function public.satisfaire_demandes(p_objet uuid, p_membre uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  with concernees as (
    update public.recherches r
       set active = false
      from public.objets o
     where o.id = p_objet
       and r.demandeur = p_membre
       and r.active
       and (
         (r.isbn is not null and o.isbn is not null and r.isbn = o.isbn)
         or (
           r.categorie is not null
           and r.categorie = o.categorie
           and (r.matiere is null or o.matiere is null or r.matiere = o.matiere)
           and (r.niveau  is null or o.niveau  is null or r.niveau  = o.niveau)
         )
       )
    returning r.id
  )
  select count(*) into n from concernees;
  return n;
end $$;

-- ---------------------------------------------------------------------
--  La confirmation d'échange retire les demandes que l'objet comble.
--  Même signature et même type de retour : pas de drop nécessaire.
-- ---------------------------------------------------------------------

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

  -- L'élève a l'objet : ses demandes correspondantes n'ont plus lieu d'être.
  perform public.satisfaire_demandes(p_objet, auth.uid());

  return o;
end $$;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

select 'retrait automatique des demandes satisfaites' as resultat;
