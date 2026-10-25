// Données de démonstration : `npm run seed`
// Remplace db.json par des utilisateurs, trajets, réservations, avis et notifications réalistes.
// L'ancien db.json est sauvegardé dans db.backup-<date>.json.
// Tous les comptes ont le mot de passe : demo123
const fs = require('fs');
const crypto = require('crypto');

const FILE = __dirname + '/db.json';
const uid = () => crypto.randomBytes(6).toString('hex');
const hash = (p, salt = crypto.randomBytes(8).toString('hex')) =>
  salt + ':' + crypto.scryptSync(p, salt, 32).toString('hex');

// Dates relatives à aujourd'hui (le jeu de données reste valable quel que soit le jour)
const day = (offset) => {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const iso = (offsetDays, hour = 9) => {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  d.setHours(hour, 0, 0, 0);
  return d.toISOString();
};

// Lieux du Grand Tunis avec coordonnées (la carte marche même sans internet pour le géocodage)
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

const users = [
  { name: 'Demo', email: 'demo@esprit.univ.tn', phone: '22111222', car: { model: 'Clio 4 grise', plate: '215 TU 4521' } },
  { name: 'Amira Ben Salah', email: 'amira.bensalah@esprit.univ.tn', phone: '23456789', car: { model: 'Peugeot 208 blanche', plate: '220 TU 1187' } },
  { name: 'Youssef Trabelsi', email: 'youssef.trabelsi@esprit.univ.tn', phone: '98765432', car: { model: 'Kia Picanto rouge', plate: '198 TU 7730' } },
  { name: 'Sarra Gharbi', email: 'sarra.gharbi@esprit.univ.tn', phone: '55123987', car: { model: '', plate: '' } },
  { name: 'Mehdi Jaziri', email: 'mehdi.jaziri@esprit.univ.tn', phone: '27894561', car: { model: 'Golf 7 noire', plate: '210 TU 3349' } },
  { name: 'Ines Mansour', email: 'ines.mansour@esprit.univ.tn', phone: '50321654', car: { model: '', plate: '' } },
].map((u) => ({ id: uid(), password: hash('demo123'), photo: null, ...u }));
const [demo, amira, youssef, sarra, mehdi, ines] = users;

const rides = [];
const bookings = [];
const reviews = [];
const notifications = [];

function ride(driver, from, to, dayOffset, time, seats, price) {
  const [fa, fo] = places[from];
  const [ta, to_] = places[to];
  const r = {
    id: uid(), driverId: driver.id, from, to, date: day(dayOffset), time, seats, seatsLeft: seats, price,
    status: 'open', fromLat: fa, fromLng: fo, toLat: ta, toLng: to_,
  };
  rides.push(r);
  return r;
}
function book(r, passenger, status, createdDaysAgo = 1) {
  const b = { id: uid(), rideId: r.id, passengerId: passenger.id, status, createdAt: iso(-createdDaysAgo) };
  if (status === 'accepted') r.seatsLeft -= 1;
  bookings.push(b);
  return b;
}
function review(r, from, to, stars, comment, daysAgo) {
  reviews.push({ id: uid(), rideId: r.id, fromId: from.id, toId: to.id, stars, comment, createdAt: iso(-daysAgo, 18) });
}
function notif(user, type, title, body, r, data, daysAgo, read = true) {
  notifications.push({
    id: uid(), userId: user.id, type, title, body, rideId: r.id,
    data: { from: r.from, to: r.to, date: r.date, time: r.time, ...data },
    read, delivered: true, createdAt: iso(-daysAgo, 10),
  });
}

// ---------- Trajets passés (terminés, avec avis) ----------
const p1 = ride(amira, 'La Marsa', 'Esprit Ghazela', -6, '08:00', 3, 4);
book(p1, demo, 'accepted', 8); book(p1, sarra, 'accepted', 8);
review(p1, demo, amira, 5, 'Très ponctuelle et conduite agréable !', 6);
review(p1, sarra, amira, 4, 'Bon trajet, musique sympa.', 5);
review(p1, amira, demo, 5, 'Passager parfait, à l\'heure.', 6);

const p2 = ride(demo, 'Ariana', 'Esprit Ghazela', -4, '08:15', 3, 3);
book(p2, ines, 'accepted', 5); book(p2, youssef, 'accepted', 5);
review(p2, ines, demo, 5, 'Super conducteur, je recommande.', 4);
review(p2, youssef, demo, 4, '', 3);

const p3 = ride(youssef, 'Tunis Centre', 'Esprit Ghazela', -3, '07:45', 4, 3.5);
book(p3, mehdi, 'accepted', 4); book(p3, ines, 'accepted', 4);
review(p3, mehdi, youssef, 3, 'Un peu en retard mais sympa.', 3);
review(p3, ines, youssef, 4, 'Trajet rapide.', 2);

const p4 = ride(mehdi, 'Bardo', 'Lac 2', -2, '17:30', 2, 5);
book(p4, demo, 'accepted', 3);
review(p4, demo, mehdi, 5, 'Voiture propre, très confortable.', 2);
review(p4, mehdi, demo, 4, '', 1);

// ---------- Trajets à venir ----------
const f1 = ride(demo, 'Esprit Ghazela', 'La Marsa', 1, '17:00', 3, 4);
book(f1, sarra, 'pending', 0); book(f1, mehdi, 'accepted', 1);
notif(demo, 'booking_new', 'Nouvelle demande', `Sarra Gharbi demande une place pour ${f1.from} → ${f1.to} (${f1.date} ${f1.time}).`, f1, { name: 'Sarra Gharbi' }, 0, false);

const f2 = ride(amira, 'La Marsa', 'Esprit Ghazela', 1, '08:00', 3, 4);
book(f2, demo, 'accepted', 1);
notif(demo, 'booking_accepted', 'Réservation acceptée ✅', `Amira Ben Salah a accepté votre demande pour ${f2.from} → ${f2.to} (${f2.date} ${f2.time}).`, f2, { name: 'Amira Ben Salah' }, 0, false);

ride(youssef, 'Tunis Centre', 'Esprit Ghazela', 2, '07:45', 4, 3.5);
const f4 = ride(mehdi, 'Manouba', 'Esprit Ghazela', 2, '08:30', 3, 4.5);
book(f4, ines, 'pending', 0);
ride(amira, 'Esprit Ghazela', 'Ariana', 3, '16:30', 2, 2.5);
ride(youssef, 'Ben Arous', 'Esprit Ghazela', 4, '07:30', 3, 5);
ride(mehdi, 'El Menzah 6', 'Raoued', 5, '12:00', 3, 3);
ride(demo, 'Esprit Ghazela', 'Tunis Centre', 6, '18:00', 4, 3.5);

// ---------- Notifications passées (déjà lues) ----------
notif(demo, 'review', 'Nouvel avis ⭐', `Ines Mansour vous a donné 5/5 pour ${p2.from} → ${p2.to}.`, p2, { name: 'Ines Mansour', stars: 5 }, 4);
notif(demo, 'review', 'Nouvel avis ⭐', `Amira Ben Salah vous a donné 5/5 pour ${p1.from} → ${p1.to}.`, p1, { name: 'Amira Ben Salah', stars: 5 }, 6);
notif(amira, 'booking_new', 'Nouvelle demande', `Demo demande une place pour ${f2.from} → ${f2.to} (${f2.date} ${f2.time}).`, f2, { name: 'Demo' }, 1);

const geocache = Object.fromEntries(Object.entries(places).map(([k, v]) => [k.toLowerCase(), v]));

if (fs.existsSync(FILE)) {
  const backup = `${__dirname}/db.backup-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  fs.copyFileSync(FILE, backup);
  console.log('Ancienne base sauvegardée :', backup);
}
fs.writeFileSync(FILE, JSON.stringify({ users, rides, bookings, tokens: {}, reviews, notifications, geocache }, null, 2));
console.log(`OK : ${users.length} utilisateurs, ${rides.length} trajets, ${bookings.length} réservations, ${reviews.length} avis.`);
console.log('Comptes (mot de passe demo123) :');
users.forEach((u) => console.log('  ' + u.email));
console.log('Redémarrez le serveur (npm start) pour charger ces données.');
