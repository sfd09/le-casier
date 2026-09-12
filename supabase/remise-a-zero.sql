-- =====================================================================
--  LE CASIER — REMISE À ZÉRO AVANT LES DÉPÔTS RÉELS
--
--  ⚠ CE FICHIER N'EST PAS UNE MIGRATION.
--    Il ne se rejoue pas, il ne s'ajoute pas à la suite 01…16.
--    Il efface définitivement les dépôts, les demandes, les
--    discussions, les photos et les comptes. Rien n'est récupérable.
--
--  Ce qui est conservé : la structure, les fonctions, les domaines
--  autorisés (monlycee.net) et toute la logique de l'application.
--  Ce qui part : les données de test, et elles seules.
--
--  À exécuter dans l'éditeur SQL de Supabase, étape par étape.
-- =====================================================================


-- ---------------------------------------------------------------------
--  ÉTAPE 1 — REGARDER AVANT D'EFFACER
--
--  Sélectionner ce bloc seul et l'exécuter. Il ne modifie rien : il
--  dit ce qui va disparaître. Une remise à zéro se décide sur des
--  nombres, pas sur une impression.
-- ---------------------------------------------------------------------

select 'comptes'            as quoi, count(*) from auth.users
union all select 'annonces',          count(*) from public.objets
union all select '  dont disponibles',count(*) from public.objets
                                       where statut <> 'echange' and not signale
union all select 'demandes',          count(*) from public.recherches
union all select 'discussions',       count(*) from public.fils
union all select 'messages',          count(*) from public.messages
union all select 'signalements',      count(*) from public.signalements
union all select 'fiches code-barres',count(*) from public.fiches
union all select 'appareils notifiés',count(*) from public.abonnements_push
union all select 'référents',         count(*) from public.referents;


-- ---------------------------------------------------------------------
--  ÉTAPE 2 — NOTER QUI EST RÉFÉRENT
--
--  Le rôle de référent est attaché à un compte. Effacer les comptes
--  l'efface aussi. Exécuter ce bloc et garder le résultat de côté :
--  il faudra redésigner la personne à l'étape 5.
-- ---------------------------------------------------------------------

select r.nom, u.email
  from public.referents r
  join auth.users u on u.id = r.id;


-- ---------------------------------------------------------------------
--  ÉTAPE 3 — EFFACER
--
--  Deux ordres suffisent. Tout le reste suit en cascade : supprimer un
--  compte supprime ses annonces, supprimer une annonce supprime ses
--  discussions, ses messages et ses signalements. C'est la structure
--  qui le garantit, pas une liste à tenir à jour.
--
--  Les fiches partent en premier parce qu'elles ne dépendent d'aucun
--  compte : elles sont la mémoire commune des codes-barres. Celles
--  créées avant le 12 septembre 2026 portent des matières fausses,
--  déduites par l'ancienne règle « la première qui accroche gagne ».
--  Or la première fiche fait foi pour tout le lycée : les garder
--  reviendrait à recopier ces erreurs sur chaque dépôt à venir.
-- ---------------------------------------------------------------------

begin;

delete from public.fiches;
delete from auth.users;

commit;


-- ---------------------------------------------------------------------
--  ÉTAPE 4 — VÉRIFIER
--
--  Tout doit être à zéro, sauf les domaines autorisés.
-- ---------------------------------------------------------------------

select 'comptes'            as quoi, count(*) from auth.users
union all select 'annonces',          count(*) from public.objets
union all select 'demandes',          count(*) from public.recherches
union all select 'discussions',       count(*) from public.fils
union all select 'messages',          count(*) from public.messages
union all select 'signalements',      count(*) from public.signalements
union all select 'fiches code-barres',count(*) from public.fiches
union all select 'appareils notifiés',count(*) from public.abonnements_push
union all select 'référents',         count(*) from public.referents
union all select 'domaines autorisés',count(*) from public.domaines_autorises;


-- ---------------------------------------------------------------------
--  ÉTAPE 5 — REDÉSIGNER LA RÉFÉRENTE
--
--  À faire seulement APRÈS qu'elle a recréé son compte dans
--  l'application, avec le nom relevé à l'étape 2. Sans cette ligne,
--  aucun signalement ne peut être tranché et la console de modération
--  reste invisible.
-- ---------------------------------------------------------------------

-- insert into public.referents (id, nom)
-- select id, 'Mme Yahia Cherif, référente' from auth.users
--  where email = 'adresse@monlycee.net'
-- on conflict (id) do nothing;
