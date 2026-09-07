// Service worker du Casier.
//
// Règle cardinale : ne JAMAIS mettre en cache les appels à la base.
// Ce sont des données vivantes ; les cacher fige le catalogue sur la
// première réponse reçue, définitivement. Seuls les fichiers de
// l'application — qui ne changent qu'à une publication — sont cachés.

const VERSION = "casier-20260907-3";
const COQUILLE = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icones/icone-192.png",
  "./icones/icone-512.png",
  "./icones/apple-touch-icon.png"
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(VERSION)
      .then((c) => c.addAll(COQUILLE))
      .then(() => self.skipWaiting())
      .catch(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((noms) => Promise.all(noms.filter((n) => n !== VERSION).map((n) => caches.delete(n))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;

  let url;
  try { url = new URL(req.url); } catch (_) { return; }

  const memeOrigine = url.origin === self.location.origin;
  const police = url.hostname === "fonts.googleapis.com" || url.hostname === "fonts.gstatic.com";

  // Tout le reste part au réseau sans interception : la base Supabase,
  // les photos, la bibliothèque cliente. Aucune donnée vivante en cache.
  if (!memeOrigine && !police) return;

  // La page : réseau d'abord, pour qu'une publication soit visible tout
  // de suite ; le cache ne sert que hors ligne.
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then((rep) => {
          const copie = rep.clone();
          caches.open(VERSION).then((c) => c.put("./index.html", copie)).catch(() => {});
          return rep;
        })
        .catch(() => caches.match("./index.html").then((r) => r || caches.match("./")))
    );
    return;
  }

  // Fichiers de l'application et polices : cache d'abord.
  e.respondWith(
    caches.match(req).then((cache) => {
      if (cache) return cache;
      return fetch(req).then((rep) => {
        if (rep && (rep.ok || rep.type === "opaque")) {
          const copie = rep.clone();
          caches.open(VERSION).then((c) => c.put(req, copie)).catch(() => {});
        }
        return rep;
      });
    })
  );
});
