// Service worker du Casier.
// Strategie : le reseau d'abord pour la page (une mise a jour est donc
// visible des le rechargement suivant), le cache d'abord pour ce qui ne
// bouge pas (icones, polices). L'application reste utilisable hors ligne.

const VERSION = "casier-v1";
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

  // La page elle-meme : reseau d'abord, cache en secours si hors ligne.
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

  // Le reste : cache d'abord, puis reseau, et on garde une copie.
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
