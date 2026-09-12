// Service worker du Casier.
//
// Règle cardinale : ne JAMAIS mettre en cache les appels à la base.
// Ce sont des données vivantes ; les cacher fige le catalogue sur la
// première réponse reçue, définitivement. Seuls les fichiers de
// l'application — qui ne changent qu'à une publication — sont cachés.

const VERSION = "casier-20260912-7";
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

// ---------------------------------------------------------------------
//  Notifications
//  Le service worker les reçoit même application fermée : c'est tout
//  l'intérêt, et c'est pourquoi ce code vit ici et non dans la page.
// ---------------------------------------------------------------------

self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { corps: e.data && e.data.text() }; }

  const titre = d.titre || "Le Casier";
  const options = {
    body: [d.corps, d.article && "\u00e0 propos de \u00ab " + d.article + " \u00bb"]
            .filter(Boolean).join("\n"),
    icon: "./icones/icone-192.png",
    badge: "./icones/icone-192.png",
    // Une seule notification par fil : dix réponses ne doivent pas
    // remplir l'écran de verrouillage de dix lignes.
    tag: d.fil ? "fil-" + d.fil : "casier",
    renotify: true,
    data: { fil: d.fil || null },
  };
  e.waitUntil(
    Promise.all([
      self.registration.showNotification(titre, options),
      // La pastille chiffrée de l'icône est posée ici aussi : au moment
      // du push, l'application est le plus souvent fermée.
      (async () => {
        try {
          if (!navigator.setAppBadge) return;
          const n = await self.registration.getNotifications();
          await navigator.setAppBadge(Math.max(1, n.length));
        } catch (_) {}
      })(),
    ])
  );
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  try { if (navigator.clearAppBadge) navigator.clearAppBadge(); } catch (_) {}
  const fil = e.notification.data && e.notification.data.fil;
  const cible = fil ? "./?fil=" + encodeURIComponent(fil) : "./";

  e.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((fenetres) => {
      // Rouvrir une fenêtre déjà ouverte plutôt qu'en empiler une autre.
      for (const f of fenetres) {
        if (f.url.includes("/le-casier") && "focus" in f) {
          if (fil && "navigate" in f) f.navigate(cible).catch(() => {});
          return f.focus();
        }
      }
      return self.clients.openWindow(cible);
    })
  );
});
