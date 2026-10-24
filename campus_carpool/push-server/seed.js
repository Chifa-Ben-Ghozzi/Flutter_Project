// Données de démonstration dans Firebase : `npm run seed`
// ⚠️ Efface les collections rides, bookings, reviews et notifications, et recrée les comptes de démo.
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

// Lieux du Grand Tunis avec coordonnées (la carte fonctionne sans géocodage)
const places = {
  'Esprit Ghazela': [36.8992, 10.1897],
  'Tunis Centre': [36.8008, 10.18],
  'La Marsa': [36.8782, 10.3247],
  'Ariana': [36.8625, 10.1956],
  'Ben Arous': [36.7531, 10.2189],
  'Manouba': [36.8101, 10.0956],
  'Lac 2': [36.8436, 10.2722],
  'El Menzah 6': [36.846, 10.18],
  'Bardo': [36.8092, 10.1408],
  'Raoued': [36.9369, 10.1866],
};

const people = [
  { key: 'demo', name: 'Demo', email: 'demo@esprit.univ.tn', phone: '22111222', carModel: 'Clio 4 grise', carPlate: '215 TU 4521' },
  { key: 'amira', name: 'Amira Ben Salah', email: 'amira.bensalah@esprit.univ.tn', phone: '23456789', carModel: 'Peugeot 208 blanche', carPlate: '220 TU 1187' },
  { key: 'youssef', name: 'Youssef Trabelsi', email: 'youssef.trabelsi@esprit.univ.tn', phone: '98765432', carModel: 'Kia Picanto rouge', carPlate: '198 TU 7730' },
  { key: 'sarra', name: 'Sarra Gharbi', email: 'sarra.gharbi@esprit.univ.tn', phone: '55123987', carModel: '', carPlate: '' },
  { key: 'mehdi', name: 'Mehdi Jaziri', email: 'mehdi.jaziri@esprit.univ.tn', phone: '27894561', carModel: 'Golf 7 noire', carPlate: '210 TU 3349' },
  { key: 'ines', name: 'Ines Mansour', email: 'ines.mansour@esprit.univ.tn', phone: '50321654', carModel: '', carPlate: '' },
];

async function clear(name) {
  const snap = await db.collection(name).get();
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = db.batch();
    snap.docs.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

(async () => {
  // ---------- Comptes (Firebase Auth) + profils (Firestore) ----------
  const u = {};
  for (const p of people) {
    try {
      const old = await auth.getUserByEmail(p.email);
      await auth.deleteUser(old.uid);
      await db.doc(`users/${old.uid}`).delete();
    } catch (_) { /* n'existait pas */ }
    const created = await auth.createUser({ email: p.email, password: 'demo123', displayName: p.name });
    u[p.key] = { uid: created.uid, name: p.name, ratingSum: 0, ratingCount: 0, ...p };
  }
  await Promise.all(['rides', 'bookings', 'reviews', 'notifications'].map(clear));

  const batch = db.batch();
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
  const p1 = ride('p1', 'amira', 'La Marsa', 'Esprit Ghazela', -6, '08:00', 3, 4);
  const b1 = book(p1, 'demo', 'accepted', 8); const b2 = book(p1, 'sarra', 'accepted', 8);
  review(p1, b1, 'demo', 'amira', 5, 'Très ponctuelle et conduite agréable !', 6);
  review(p1, b2, 'sarra', 'amira', 4, 'Bon trajet, musique sympa.', 5);
  review(p1, b1, 'amira', 'demo', 5, 'Passager parfait, à l\'heure.', 6);

  const p2 = ride('p2', 'demo', 'Ariana', 'Esprit Ghazela', -4, '08:15', 3, 3);
  const b3 = book(p2, 'ines', 'accepted', 5); const b4 = book(p2, 'youssef', 'accepted', 5);
  review(p2, b3, 'ines', 'demo', 5, 'Super conducteur, je recommande.', 4);
  review(p2, b4, 'youssef', 'demo', 4, '', 3);

  const p3 = ride('p3', 'youssef', 'Tunis Centre', 'Esprit Ghazela', -3, '07:45', 4, 3.5);
  const b5 = book(p3, 'mehdi', 'accepted', 4); const b6 = book(p3, 'ines', 'accepted', 4);
  review(p3, b5, 'mehdi', 'youssef', 3, 'Un peu en retard mais sympa.', 3);
  review(p3, b6, 'ines', 'youssef', 4, 'Trajet rapide.', 2);

  const p4 = ride('p4', 'mehdi', 'Bardo', 'Lac 2', -2, '17:30', 2, 5);
  const b7 = book(p4, 'demo', 'accepted', 3);
  review(p4, b7, 'demo', 'mehdi', 5, 'Voiture propre, très confortable.', 2);
  review(p4, b7, 'mehdi', 'demo', 4, '', 1);

  // ---------- Trajets à venir ----------
  const f1 = ride('f1', 'demo', 'Esprit Ghazela', 'La Marsa', 1, '17:00', 3, 4);
  book(f1, 'sarra', 'pending', 0); book(f1, 'mehdi', 'accepted', 1);
  notif('demo', 'booking_new', f1, { name: 'Sarra Gharbi' }, 0, false);

  const f2 = ride('f2', 'amira', 'La Marsa', 'Esprit Ghazela', 1, '08:00', 3, 4);
  book(f2, 'demo', 'accepted', 1);
  notif('demo', 'booking_accepted', f2, { name: 'Amira Ben Salah' }, 0, false);

  ride('f3', 'youssef', 'Tunis Centre', 'Esprit Ghazela', 2, '07:45', 4, 3.5);
  const f4 = ride('f4', 'mehdi', 'Manouba', 'Esprit Ghazela', 2, '08:30', 3, 4.5);
  book(f4, 'ines', 'pending', 0);
  ride('f5', 'amira', 'Esprit Ghazela', 'Ariana', 3, '16:30', 2, 2.5);
  ride('f6', 'youssef', 'Ben Arous', 'Esprit Ghazela', 4, '07:30', 3, 5);
  ride('f7', 'mehdi', 'El Menzah 6', 'Raoued', 5, '12:00', 3, 3);
  ride('f8', 'demo', 'Esprit Ghazela', 'Tunis Centre', 6, '18:00', 4, 3.5);

  notif('demo', 'review', p2, { name: 'Ines Mansour', stars: 5 }, 4);
  notif('demo', 'review', p1, { name: 'Amira Ben Salah', stars: 5 }, 6);
  notif('amira', 'booking_new', f2, { name: 'Demo' }, 1);

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
  await batch.commit();

  console.log(`OK : ${people.length} comptes, ${Object.keys(rides).length} trajets, ${bookings.length} réservations.`);
  console.log('Comptes (mot de passe demo123) :');
  people.forEach((p) => console.log('  ' + p.email));
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
