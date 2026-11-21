// Données de démonstration dans Firebase : `npm run seed`
// ⚠️ VIDE TOUTE LA BASE : tous les comptes (Firebase Auth) et toutes les collections
// (users, rides, bookings, reviews, notifications, messages, alerts), puis recrée les données de démo.
// Tous les comptes ont le mot de passe : demo123
const admin = require('firebase-admin');
const path = require('path');

admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, 'service-account.json'))) });
const db = admin.firestore();
const auth = admin.auth();
const { Timestamp, FieldValue } = admin.firestore;

const day = (offset) => {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const ago = (days, hour = 9) => {
  const d = new Date();
  d.setDate(d.getDate() - days);
  d.setHours(hour, 0, 0, 0);
  return Timestamp.fromDate(d);
};

// Lieux avec coordonnées (la carte fonctionne sans géocodage).
// Noms sans accent : la recherche compare le texte tel quel (« rades » trouve « Rades »).
const places = {
  'Esprit Ghazela': [36.8992, 10.1897],
  'Centre Urbain Nord (CUN)': [36.8466, 10.1965],
  'Ariana': [36.8625, 10.1956],
  'Ennasr': [36.859, 10.165],
  'Tunis Centre': [36.8008, 10.18],
  'Ben Arous': [36.7531, 10.2189],
  'Rades': [36.7681, 10.2753],
  'El Mourouj': [36.729, 10.209],
  'La Marsa': [36.8782, 10.3247],
  'Lac 2': [36.8436, 10.2722],
  'Bardo': [36.8092, 10.1408],
  'Hammamet': [36.4, 10.6167],
  'Nabeul': [36.4561, 10.7376],
  'Sousse': [35.8256, 10.6084],
  'Monastir': [35.7643, 10.8113],
  'Sfax': [34.7406, 10.7603],
};

// Numéros de téléphone fictifs
const people = [
  { key: 'demo', name: 'Demo', email: 'demo@esprit.univ.tn', phone: '22111222', carModel: 'Clio 4 grise', carPlate: '215 TU 4521' },
  { key: 'mariem', name: 'Mariem Bouchaala', email: 'mariem.bouchaala@esprit.univ.tn', phone: '23456789', carModel: 'Peugeot 208 blanche', carPlate: '220 TU 1187' },
  { key: 'baha', name: 'Baha Sallami', email: 'baha.sallami@esprit.univ.tn', phone: '98765432', carModel: 'Kia Rio grise', carPlate: '212 TU 7730' },
  { key: 'chifa', name: 'Chifa Ben Ghozzi', email: 'chifa.benghozzi@esprit.univ.tn', phone: '55123987', carModel: 'Volkswagen Polo bleue', carPlate: '218 TU 6402' },
  { key: 'eya', name: 'Eya Chibni', email: 'eya.chibni@esprit.univ.tn', phone: '27894561', carModel: 'Hyundai i10 rouge', carPlate: '205 TU 3349' },
];

// Écritures regroupées puis envoyées par paquets (Firestore : 500 opérations max par batch)
const writes = [];
const batch = { set: (ref, data) => writes.push([ref, data]) };
async function commitAll() {
  for (let i = 0; i < writes.length; i += 400) {
    const b = db.batch();
    writes.slice(i, i + 400).forEach(([ref, data]) => b.set(ref, data));
    await b.commit();
  }
}

async function clear(name) {
  const snap = await db.collection(name).get();
  for (let i = 0; i < snap.docs.length; i += 400) {
    const b = db.batch();
    snap.docs.slice(i, i + 400).forEach((d) => b.delete(d.ref));
    await b.commit();
  }
}

async function deleteAllAccounts() {
  let total = 0;
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    if (page.users.length) await auth.deleteUsers(page.users.map((u) => u.uid));
    total += page.users.length;
    pageToken = page.pageToken;
  } while (pageToken);
  return total;
}

(async () => {
  // ---------- Base vidée ----------
  const deleted = await deleteAllAccounts();
  await Promise.all(['users', 'rides', 'bookings', 'reviews', 'notifications', 'messages', 'alerts'].map(clear));
  console.log(`Base vidée (${deleted} comptes supprimés).`);

  // ---------- Comptes (Firebase Auth) ----------
  const u = {};
  for (const p of people) {
    const created = await auth.createUser({ email: p.email, password: 'demo123', displayName: p.name });
    u[p.key] = { uid: created.uid, ratingSum: 0, ratingCount: 0, ...p };
  }

  const rides = {};
  let n = 0;

  function ride(key, driver, from, to, dayOffset, time, seats, price) {
    const [fa, fo] = places[from];
    const [ta, to_] = places[to];
    const date = day(dayOffset);
    const r = {
      driverId: u[driver].uid, from, to, date, time,
      dateTime: Timestamp.fromDate(new Date(`${date}T${time}:00`)),
      seats, seatsLeft: seats, price, status: 'open',
      fromLat: fa, fromLng: fo, toLat: ta, toLng: to_, createdAt: ago(10),
    };
    rides[key] = { id: key, ...r };
    return rides[key];
  }
  const bookings = [];
  function book(r, passenger, status, daysAgo = 1) {
    const id = `b${++n}`;
    if (status === 'accepted') r.seatsLeft -= 1;
    bookings.push({ id, rideId: r.id, passengerId: u[passenger].uid, driverId: r.driverId, status, createdAt: ago(daysAgo) });
    return id;
  }
  function review(r, bookingId, from, to, stars, comment, daysAgo) {
    const id = `${r.id}_${u[from].uid}_${u[to].uid}`;
    batch.set(db.doc(`reviews/${id}`), {
      rideId: r.id, bookingId, fromId: u[from].uid, fromName: u[from].name, toId: u[to].uid,
      stars, comment, createdAt: ago(daysAgo, 18),
    });
    u[to].ratingSum += stars;
    u[to].ratingCount += 1;
  }
  function notif(to, type, r, extra, daysAgo, read = true) {
    batch.set(db.collection('notifications').doc(), {
      userId: u[to].uid, type, rideId: r.id,
      data: { from: r.from, to: r.to, date: r.date, time: r.time, ...extra },
      read, pushed: true, createdAt: ago(daysAgo, 10), // pushed: true -> pas de push pour l'historique
    });
  }

  // ---------- Trajets passés (terminés, avec avis) ----------
  const p1 = ride('p1', 'mariem', 'Ariana', 'Esprit Ghazela', -6, '08:00', 3, 3);
  const b1 = book(p1, 'demo', 'accepted', 8); const b2 = book(p1, 'eya', 'accepted', 8);
  review(p1, b1, 'demo', 'mariem', 5, 'Très ponctuelle et conduite agréable !', 6);
  review(p1, b2, 'eya', 'mariem', 5, 'Comme d\'habitude, parfait.', 5);
  review(p1, b1, 'mariem', 'demo', 5, 'Passager parfait, à l\'heure.', 6);

  const p2 = ride('p2', 'baha', 'Rades', 'Esprit Ghazela', -5, '07:30', 4, 4.5);
  const b3 = book(p2, 'demo', 'accepted', 6); const b4 = book(p2, 'chifa', 'accepted', 6);
  review(p2, b3, 'demo', 'baha', 4, 'Bon trajet, un peu de bouchons à l\'entrée de Tunis.', 5);
  review(p2, b4, 'chifa', 'baha', 5, 'Voiture propre, très confortable.', 4);

  const p3 = ride('p3', 'chifa', 'Sousse', 'Tunis Centre', -4, '07:00', 3, 15);
  const b5 = book(p3, 'eya', 'accepted', 5);
  review(p3, b5, 'eya', 'chifa', 5, 'Autoroute A1 sans souci, je recommande.', 3);
  review(p3, b5, 'chifa', 'eya', 5, '', 3);

  const p4 = ride('p4', 'eya', 'Hammamet', 'Esprit Ghazela', -3, '07:00', 3, 10);
  const b6 = book(p4, 'mariem', 'accepted', 4);
  review(p4, b6, 'mariem', 'eya', 4, 'Départ à l\'heure, sympa.', 2);

  const p5 = ride('p5', 'demo', 'Centre Urbain Nord (CUN)', 'Ariana', -2, '17:30', 3, 2);
  const b7 = book(p5, 'baha', 'accepted', 3);
  review(p5, b7, 'baha', 'demo', 5, 'Super conducteur.', 1);

  // ---------- Trajets à venir ----------
  // Demain
  const f1 = ride('f1', 'demo', 'Esprit Ghazela', 'Centre Urbain Nord (CUN)', 1, '17:00', 3, 2.5);
  const bChifa = book(f1, 'chifa', 'pending', 0); book(f1, 'baha', 'accepted', 1);
  notif('demo', 'booking_new', f1, { name: 'Chifa Ben Ghozzi' }, 0, false);

  const f2 = ride('f2', 'mariem', 'Ariana', 'Esprit Ghazela', 1, '08:00', 3, 3);
  const bDemo = book(f2, 'demo', 'accepted', 1);
  notif('demo', 'booking_accepted', f2, { name: 'Mariem Bouchaala' }, 0, false);

  ride('f3', 'baha', 'Rades', 'Esprit Ghazela', 1, '07:30', 4, 4.5);
  ride('f4', 'chifa', 'Ennasr', 'Esprit Ghazela', 1, '08:15', 3, 2.5);

  // Dans 2 jours : correspondance Sfax -> Sousse puis Sousse -> Tunis
  const f5 = ride('f5', 'baha', 'Ben Arous', 'Esprit Ghazela', 2, '07:45', 3, 4.5);
  book(f5, 'eya', 'pending', 0);
  ride('f6', 'chifa', 'Sfax', 'Sousse', 2, '06:30', 3, 12);
  ride('f7', 'eya', 'Sousse', 'Tunis Centre', 2, '09:15', 3, 15);
  const f8 = ride('f8', 'mariem', 'Esprit Ghazela', 'Ariana', 2, '16:30', 2, 3); // complet
  book(f8, 'eya', 'accepted', 1); book(f8, 'chifa', 'accepted', 1);

  // Dans 3 jours
  const f9 = ride('f9', 'chifa', 'Sousse', 'Esprit Ghazela', 3, '06:45', 3, 16);
  ride('f10', 'eya', 'Hammamet', 'Esprit Ghazela', 3, '07:00', 3, 10);
  ride('f11', 'mariem', 'Esprit Ghazela', 'Tunis Centre', 3, '18:00', 4, 3.5);
  ride('f12', 'baha', 'El Mourouj', 'Centre Urbain Nord (CUN)', 3, '08:00', 3, 3);

  // Dans 4 à 7 jours
  ride('f13', 'demo', 'Tunis Centre', 'Hammamet', 4, '14:00', 3, 9);
  ride('f14', 'baha', 'Esprit Ghazela', 'Rades', 4, '17:30', 4, 4.5);
  ride('f15', 'eya', 'Lac 2', 'La Marsa', 4, '12:30', 3, 3);
  ride('f16', 'mariem', 'Centre Urbain Nord (CUN)', 'Esprit Ghazela', 5, '08:30', 3, 2.5);
  ride('f17', 'chifa', 'Tunis Centre', 'Sfax', 5, '16:00', 3, 25);
  ride('f18', 'mariem', 'Bardo', 'Esprit Ghazela', 5, '07:50', 3, 3.5);
  // Correspondance Nabeul -> Hammamet puis Hammamet -> Esprit
  ride('f19', 'eya', 'Nabeul', 'Hammamet', 6, '07:30', 3, 2.5);
  ride('f20', 'baha', 'Hammamet', 'Esprit Ghazela', 6, '08:30', 3, 10);
  ride('f21', 'demo', 'Ariana', 'Esprit Ghazela', 6, '08:00', 3, 3);
  ride('f22', 'chifa', 'Monastir', 'Sousse', 7, '08:00', 3, 4);
  ride('f23', 'mariem', 'Esprit Ghazela', 'Hammamet', 7, '17:00', 3, 10);

  // ---------- Trajet régulier : Baha, Rades -> Esprit, lundi à vendredi pendant 2 semaines ----------
  for (let i = 8; i <= 21; i++) {
    const d = new Date(); d.setDate(d.getDate() + i);
    if (d.getDay() === 0 || d.getDay() === 6) continue; // pas le week-end
    ride(`s${i}`, 'baha', 'Rades', 'Esprit Ghazela', i, '07:30', 4, 4.5).seriesId = 'baha-rades-esprit';
  }

  // ---------- Messagerie ----------
  function msg(r, bookingId, from, to, text, minutesAgo, read = true) {
    const createdAt = Timestamp.fromDate(new Date(Date.now() - minutesAgo * 60000));
    batch.set(db.collection('messages').doc(), {
      bookingId, rideId: r.id, from: u[from].uid, to: u[to].uid, fromName: u[from].name, toName: u[to].name,
      route: `${r.from} → ${r.to}`, text, createdAt, read, pushed: true, // pushed: true -> pas de push pour l'historique
    });
  }
  msg(f2, bDemo, 'demo', 'mariem', 'Bonjour Mariem, où est-ce qu\'on se retrouve demain ?', 95);
  msg(f2, bDemo, 'mariem', 'demo', 'Bonjour ! Devant la station de métro Ariana, à 7h55.', 80);
  msg(f2, bDemo, 'demo', 'mariem', 'Parfait, merci 🙏', 78);
  msg(f2, bDemo, 'mariem', 'demo', 'Je serai dans une Peugeot 208 blanche, à demain !', 20, false);
  msg(f1, bChifa, 'chifa', 'demo', 'Salut ! Tu peux me déposer devant la tour du CUN ?', 35, false);

  // ---------- Alertes de trajet ----------
  const alert = (who, from, to, maxPrice = null) => batch.set(db.collection('alerts').doc(), {
    userId: u[who].uid, from, to, maxPrice, createdAt: ago(2),
  });
  alert('demo', 'Sousse', 'Esprit');
  alert('demo', '', 'Hammamet', 10);
  alert('eya', 'Esprit', 'CUN');

  notif('demo', 'ride_alert', f9, { name: 'Chifa Ben Ghozzi', price: 16, count: 1 }, 1);
  notif('demo', 'review', p5, { name: 'Baha Sallami', stars: 5 }, 1);
  notif('demo', 'review', p1, { name: 'Mariem Bouchaala', stars: 5 }, 6);
  notif('mariem', 'booking_new', f2, { name: 'Demo' }, 1);

  for (const r of Object.values(rides)) {
    const { id, ...data } = r;
    batch.set(db.doc(`rides/${id}`), data);
  }
  for (const b of bookings) {
    const { id, ...data } = b;
    batch.set(db.doc(`bookings/${id}`), data);
  }
  for (const p of Object.values(u)) {
    batch.set(db.doc(`users/${p.uid}`), {
      email: p.email, name: p.name, phone: p.phone, carModel: p.carModel, carPlate: p.carPlate,
      photo: null, ratingSum: p.ratingSum, ratingCount: p.ratingCount, fcmTokens: [], lang: 'fr',
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  await commitAll();

  console.log(`OK : ${people.length} comptes, ${Object.keys(rides).length} trajets, ${bookings.length} réservations, messages et alertes de démo.`);
  console.log('Comptes (mot de passe demo123) :');
  people.forEach((p) => console.log('  ' + p.email));
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
