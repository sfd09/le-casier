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
      "Urgency": "normal",
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

Deno.serve(async (req) => {
  const repondre = (o: unknown) =>
    new Response(JSON.stringify(o), { status: 200, headers: { "Content-Type": "application/json" } });

  try {
    const recu = await req.json().catch(() => ({}));
    // Le webhook envoie { type, table, record }. On accepte aussi un
    // appel direct { fil, auteur, texte } pour pouvoir tester à la main.
    const m = recu.record ?? recu;
    if (!m?.fil || !m?.auteur) return repondre({ ignore: "message incomplet" });

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

    await Promise.all(abos.map(async (a) => {
      try {
        const r = await pousser(a, charge);
        if (r.ok) envoyes++;
        // 404/410 : application désinstallée ou autorisation révoquée.
        // On nettoie plutôt que de réessayer indéfiniment.
        else if (r.status === 404 || r.status === 410) perimes.push(a.endpoint);
        else await db.from("abonnements_push")
                     .update({ echecs: (a.echecs ?? 0) + 1 }).eq("endpoint", a.endpoint);
      } catch (_) {
        await db.from("abonnements_push")
                .update({ echecs: (a.echecs ?? 0) + 1 }).eq("endpoint", a.endpoint);
      }
    }));

    if (perimes.length) await db.from("abonnements_push").delete().in("endpoint", perimes);
    return repondre({ envoyes, nettoyes: perimes.length });
  } catch (e) {
    // On répond 200 : un échec de notification ne doit jamais faire
    // échouer l'enregistrement du message lui-même.
    return repondre({ erreur: String(e) });
  }
});
