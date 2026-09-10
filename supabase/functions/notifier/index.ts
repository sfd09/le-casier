// =====================================================================
//  LE CASIER — expédition des notifications push
// =====================================================================
//
//  Appelée par un webhook de la base à chaque nouveau message. Elle
//  cherche le destinataire — l'autre participant du fil — et pousse la
//  notification vers chacun de ses appareils.
//
//  Elle seule détient la clé privée VAPID : une page statique servie par
//  GitHub Pages ne peut rien garder de secret.

import { createClient } from "jsr:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const PUBLIQUE = Deno.env.get("VAPID_PUBLIC_KEY")!;
const PRIVEE   = Deno.env.get("VAPID_PRIVATE_KEY")!;
const SUJET    = Deno.env.get("VAPID_SUBJECT") ?? "mailto:contact@le-casier";

webpush.setVapidDetails(SUJET, PUBLIQUE, PRIVEE);

// Le service_role contourne les politiques de sécurité : indispensable
// ici, puisqu'on lit les abonnements de quelqu'un d'autre que l'appelant.
const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function court(t: string, n: number) {
  t = (t ?? "").replace(/\s+/g, " ").trim();
  return t.length <= n ? t : t.slice(0, n - 1) + "…";
}

Deno.serve(async (req) => {
  try {
    const corps = await req.json();
    // Le webhook envoie { type, table, record }. On accepte aussi un
    // appel direct { fil, auteur, texte } pour pouvoir tester à la main.
    const m = corps.record ?? corps;
    if (!m?.fil || !m?.auteur) {
      return new Response(JSON.stringify({ ignore: "message incomplet" }), { status: 200 });
    }

    const { data: fil } = await db.from("fils")
      .select("proprietaire, demandeur, objet").eq("id", m.fil).maybeSingle();
    if (!fil) return new Response(JSON.stringify({ ignore: "fil inconnu" }), { status: 200 });

    // Le destinataire est celui des deux qui n'a pas écrit.
    const pour = fil.proprietaire === m.auteur ? fil.demandeur : fil.proprietaire;

    const [{ data: expediteur }, { data: article }, { data: abos }] = await Promise.all([
      db.from("membres").select("pseudo").eq("id", m.auteur).maybeSingle(),
      db.from("objets").select("titre").eq("id", fil.objet).maybeSingle(),
      db.from("abonnements_push").select("*").eq("membre", pour),
    ]);

    if (!abos?.length) {
      return new Response(JSON.stringify({ envoyes: 0, raison: "aucun appareil" }), { status: 200 });
    }

    const charge = JSON.stringify({
      titre: `${expediteur?.pseudo ?? "Un élève"} vous a répondu`,
      corps: court(m.texte ?? "", 120),
      article: court(article?.titre ?? "", 60),
      fil: m.fil,
    });

    let envoyes = 0;
    const perimes: string[] = [];

    await Promise.all(abos.map(async (a) => {
      try {
        await webpush.sendNotification(
          { endpoint: a.endpoint, keys: { p256dh: a.p256dh, auth: a.auth } },
          charge,
          { TTL: 86400, urgency: "normal" },
        );
        envoyes++;
      } catch (e) {
        // 404 ou 410 : l'appareil a désinstallé l'application ou révoqué
        // l'autorisation. On nettoie plutôt que de réessayer indéfiniment.
        const code = (e as { statusCode?: number }).statusCode;
        if (code === 404 || code === 410) perimes.push(a.endpoint);
        else await db.from("abonnements_push")
                     .update({ echecs: (a.echecs ?? 0) + 1 }).eq("endpoint", a.endpoint);
      }
    }));

    if (perimes.length) {
      await db.from("abonnements_push").delete().in("endpoint", perimes);
    }

    return new Response(JSON.stringify({ envoyes, nettoyes: perimes.length }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    // On répond 200 : un échec de notification ne doit jamais faire
    // échouer l'envoi du message lui-même côté base.
    return new Response(JSON.stringify({ erreur: String(e) }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }
});
