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
//
//  Le chiffrement suit les RFC 8291 (aes128gcm) et 8292 (VAPID), écrit
//  avec les primitives natives. La bibliothèque « web-push » d'usage
//  courant dépend de modules Node absents de cet environnement.

import { createClient } from "jsr:@supabase/supabase-js@2";

const PUBLIQUE = Deno.env.get("VAPID_PUBLIC_KEY")!;
const PRIVEE   = Deno.env.get("VAPID_PRIVATE_KEY")!;
const SUJET    = Deno.env.get("VAPID_SUBJECT") ?? "mailto:contact@le-casier";

/* ---------------- outils base64url ---------------- */

function versOctets(b64: string): Uint8Array {
  const p = "=".repeat((4 - (b64.length % 4)) % 4);
  const brut = atob((b64 + p).replace(/-/g, "+").replace(/_/g, "/"));
  const t = new Uint8Array(brut.length);
  for (let i = 0; i < brut.length; i++) t[i] = brut.charCodeAt(i);
  return t;
}

function versB64(o: Uint8Array): string {
  let s = "";
  for (let i = 0; i < o.length; i++) s += String.fromCharCode(o[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const utf8 = (s: string) => new TextEncoder().encode(s);

function coller(...parts: Uint8Array[]): Uint8Array {
  const n = parts.reduce((t, p) => t + p.length, 0);
  const out = new Uint8Array(n);
  let d = 0;
  for (const p of parts) { out.set(p, d); d += p.length; }
  return out;
}

/* ---------------- chiffrement du contenu (RFC 8291) ---------------- */

async function hkdf(sel: Uint8Array, ikm: Uint8Array, info: Uint8Array, taille: number) {
  const k = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt: sel, info }, k, taille * 8));
}

export async function chiffrer(
  texte: string, p256dh: string, authSecret: string,
  selImpose?: Uint8Array, paireImposee?: CryptoKeyPair,
): Promise<Uint8Array> {
  const ua = versOctets(p256dh);          // clé publique de l'appareil, 65 octets
  const secret = versOctets(authSecret);  // 16 octets
  const sel = selImpose ?? crypto.getRandomValues(new Uint8Array(16));

  // Paire éphémère : une par envoi, jamais réutilisée.
  const paire = paireImposee ?? await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]) as CryptoKeyPair;
  const asPub = new Uint8Array(await crypto.subtle.exportKey("raw", paire.publicKey));

  const cleUa = await crypto.subtle.importKey(
    "raw", ua, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const partage = new Uint8Array(await crypto.subtle.deriveBits(
    { name: "ECDH", public: cleUa }, paire.privateKey, 256));

  // Le secret d'authentification sert de sel à la première dérivation ;
  // le contexte lie la clé aux deux interlocuteurs.
  const ikm = await hkdf(secret, partage,
    coller(utf8("WebPush: info\0"), ua, asPub), 32);

  const cle   = await hkdf(sel, ikm, utf8("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(sel, ikm, utf8("Content-Encoding: nonce\0"), 12);

  const aes = await crypto.subtle.importKey("raw", cle, "AES-GCM", false, ["encrypt"]);
  // 0x02 marque le dernier bloc ; sans ce délimiteur le navigateur rejette.
  const clair = coller(utf8(texte), new Uint8Array([2]));
  const chiffre = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce }, aes, clair));

  const rs = new Uint8Array(4);
  new DataView(rs.buffer).setUint32(0, 4096);
  return coller(sel, rs, new Uint8Array([asPub.length]), asPub, chiffre);
}

/* ---------------- signature VAPID (RFC 8292) ---------------- */

async function clePrivee(): Promise<CryptoKey> {
  const pub = versOctets(PUBLIQUE);   // 0x04 || x(32) || y(32)
  return crypto.subtle.importKey("jwk", {
    kty: "EC", crv: "P-256", d: PRIVEE,
    x: versB64(pub.slice(1, 33)), y: versB64(pub.slice(33, 65)),
    ext: true, key_ops: ["sign"],
  }, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

async function entete(endpoint: string): Promise<string> {
  const aud = new URL(endpoint).origin;
  const tete = versB64(utf8(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const corps = versB64(utf8(JSON.stringify({
    aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: SUJET,
  })));
  const aSigner = tete + "." + corps;
  const sig = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, await clePrivee(), utf8(aSigner)));
  return `vapid t=${aSigner}.${versB64(sig)}, k=${PUBLIQUE}`;
}

/* ---------------- envoi ---------------- */

async function pousser(abo: { endpoint: string; p256dh: string; auth: string }, charge: string) {
  const corps = await chiffrer(charge, abo.p256dh, abo.auth);
  return fetch(abo.endpoint, {
    method: "POST",
    headers: {
      "Authorization": await entete(abo.endpoint),
      "Content-Encoding": "aes128gcm",
      "Content-Type": "application/octet-stream",
      "TTL": "86400",
      // iOS regroupe et diffère les notifications pour économiser la
      // batterie. « high » demande une remise sans attente : c'est ce
      // qui distingue un message d'une lettre d'information.
      "Urgency": "high",
    },
    body: corps,
  });
}

/* ---------------- point d'entrée ---------------- */

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function court(t: string, n: number) {
  t = (t ?? "").replace(/\s+/g, " ").trim();
  return t.length <= n ? t : t.slice(0, n - 1) + "…";
}

// Une annonce vient d'être déposée : on cherche les demandes qu'elle
// satisfait et on prévient ceux qui les ont publiées. La règle de
// correspondance est dans la base, pas ici : elle doit pouvoir être
// ajustée sans redéployer.
async function annoncerCorrespondances(objetId: string) {
  const reponse = (o: unknown) =>
    new Response(JSON.stringify(o), { status: 200, headers: { "Content-Type": "application/json" } });

  const { data: article } = await db.from("objets")
    .select("titre, mode, prix, proprietaire").eq("id", objetId).maybeSingle();
  if (!article) return reponse({ ignore: "annonce inconnue" });

  const { data: cibles } = await db.rpc("correspondances", { p_objet: objetId });
  if (!cibles?.length) return reponse({ envoyes: 0, raison: "aucune demande correspondante" });

  const valeur = article.mode === "don" ? "gratuit"
               : article.mode === "vente" ? `${article.prix} €`
               : "1 crédit";

  let envoyes = 0;
  const perimes: string[] = [];
  const detail: string[] = [];   // ce qui s'est réellement passé, par appareil

  for (const cible of cibles) {
    const { data: abos } = await db.from("abonnements_push").select("*").eq("membre", cible.membre);
    if (!abos?.length) {
      detail.push(`${String(cible.membre).slice(0, 8)}: aucun appareil abonné`);
      continue;
    }

    const charge = JSON.stringify({
      titre: "Ce que vous cherchez vient d'être déposé",
      corps: `${court(article.titre, 70)} — ${valeur}`,
      article: court(cible.demande ?? "", 60),
      fil: null,
    });

    await Promise.all(abos.map(async (a) => {
      try {
        const r = await pousser(a, charge);
        if (r.ok) { envoyes++; detail.push("envoyé " + r.status); }
        else {
          detail.push("refusé " + r.status + " " + (await r.text()).slice(0, 90));
          if (r.status === 404 || r.status === 410) perimes.push(a.endpoint);
        }
      } catch (e) {
        detail.push("exception " + String(e).slice(0, 90));
      }
    }));
  }

  if (perimes.length) await db.from("abonnements_push").delete().in("endpoint", perimes);
  return reponse({ envoyes, demandes: cibles.length, nettoyes: perimes.length, detail });
}

// Route de diagnostic : indique lequel des éléments base64 est illisible,
// sans jamais révéler les valeurs elles-mêmes.
function inspecter(nom: string, v: string | undefined) {
  if (v === undefined || v === null) return `${nom}: ABSENT`;
  const brut = String(v);
  const propre = brut.trim();
  const suspect = brut !== propre ? " (espaces ou saut de ligne !)" : "";
  try {
    const o = versOctets(propre);
    return `${nom}: ${propre.length} car → ${o.length} octets${suspect}`;
  } catch (e) {
    return `${nom}: ${propre.length} car → ILLISIBLE${suspect}`;
  }
}

Deno.serve(async (req) => {
  const repondre = (o: unknown) =>
    new Response(JSON.stringify(o), { status: 200, headers: { "Content-Type": "application/json" } });

  try {
    const recu = await req.json().catch(() => ({}));

    if (recu.diagnostic) {
      const lignes = [
        inspecter("VAPID_PUBLIC_KEY", PUBLIQUE),
        inspecter("VAPID_PRIVATE_KEY", PRIVEE),
        `VAPID_SUBJECT: ${SUJET}`,
      ];
      const { data: abos } = await db.from("abonnements_push").select("p256dh, auth, endpoint");
      for (const a of (abos ?? [])) {
        lignes.push(inspecter("p256dh", a.p256dh) + " | " + inspecter("auth", a.auth) +
                    " | " + new URL(a.endpoint).host);
      }
      if (!abos?.length) lignes.push("aucun abonnement enregistré");
      return repondre({ diagnostic: lignes });
    }

    const envoye = recu.record ?? recu;
    if (!envoye?.id) return repondre({ ignore: "message incomplet" });

    // Deux déclencheurs mènent ici : un nouveau message, ou une annonce
    // qui répond peut-être à une demande en attente.
    if (recu.table === "objets") return await annoncerCorrespondances(envoye.id);

    // On relit le message dans la base au lieu de croire l'appelant.
    // La fonction est joignable avec la clé publique : sans cela, on
    // pourrait lui faire expédier n'importe quel texte à n'importe qui.
    const { data: m } = await db.from("messages")
      .select("fil, auteur, texte").eq("id", envoye.id).maybeSingle();
    if (!m) return repondre({ ignore: "message inconnu" });

    const { data: fil } = await db.from("fils")
      .select("proprietaire, demandeur, objet").eq("id", m.fil).maybeSingle();
    if (!fil) return repondre({ ignore: "fil inconnu" });

    // Le destinataire est celui des deux qui n'a pas écrit.
    const pour = fil.proprietaire === m.auteur ? fil.demandeur : fil.proprietaire;

    const [{ data: qui }, { data: article }, { data: abos }] = await Promise.all([
      db.from("membres").select("pseudo").eq("id", m.auteur).maybeSingle(),
      db.from("objets").select("titre").eq("id", fil.objet).maybeSingle(),
      db.from("abonnements_push").select("*").eq("membre", pour),
    ]);

    if (!abos?.length) return repondre({ envoyes: 0, raison: "aucun appareil" });

    const charge = JSON.stringify({
      titre: `${qui?.pseudo ?? "Un élève"} vous a répondu`,
      corps: court(m.texte ?? "", 120),
      article: court(article?.titre ?? "", 60),
      fil: m.fil,
    });

    let envoyes = 0;
    const perimes: string[] = [];

    const detail: string[] = [];
    await Promise.all(abos.map(async (a) => {
      try {
        const r = await pousser(a, charge);
        if (r.ok) { envoyes++; detail.push("envoyé " + r.status); }
        // 404/410 : application désinstallée ou autorisation révoquée.
        // On nettoie plutôt que de réessayer indéfiniment.
        else if (r.status === 404 || r.status === 410) {
          detail.push("périmé " + r.status);
          perimes.push(a.endpoint);
        } else {
          detail.push("refusé " + r.status + " " + (await r.text()).slice(0, 90));
          await db.from("abonnements_push")
                  .update({ echecs: (a.echecs ?? 0) + 1 }).eq("endpoint", a.endpoint);
        }
      } catch (e) {
        detail.push("exception " + String(e).slice(0, 90));
        await db.from("abonnements_push")
                .update({ echecs: (a.echecs ?? 0) + 1 }).eq("endpoint", a.endpoint);
      }
    }));

    if (perimes.length) await db.from("abonnements_push").delete().in("endpoint", perimes);
    return repondre({ envoyes, nettoyes: perimes.length, detail });
  } catch (e) {
    // On répond 200 : un échec de notification ne doit jamais faire
    // échouer l'enregistrement du message lui-même.
    return repondre({ erreur: String(e) });
  }
});
