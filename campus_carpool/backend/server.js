// Backend simple : Express + fichier JSON (db.json). Aucune base de données à installer.
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const crypto = require('crypto');

const app = express();
app.use(cors());
app.use(express.json({ limit: '5mb' }));

const FILE = __dirname + '/db.json';
let db = { users: [], rides: [], bookings: [], tokens: {} };
if (fs.existsSync(FILE)) db = JSON.parse(fs.readFileSync(FILE, 'utf8'));
db.reviews = db.reviews || [];
db.notifications = db.notifications || [];
db.geocache = db.geocache || {};
const save = () => fs.writeFileSync(FILE, JSON.stringify(db, null, 2));
const uid = () => crypto.randomBytes(6).toString('hex');
const hash = (p, salt = crypto.randomBytes(8).toString('hex')) =>
  salt + ':' + crypto.scryptSync(p, salt, 32).toString('hex');
const checkPwd = (p, h) => hash(p, h.split(':')[0]) === h;

// Email universitaire : domaine contenant "univ", ou finissant par .edu / .ac.xx (modifiable)
const isUniEmail = (e) =>
  /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) &&
  /(^|\.)(edu|ac)(\.|$)|univ/i.test(e.split('@')[1]);

// Note moyenne reçue par un utilisateur (null si aucun avis)
const ratingOf = (userId) => {
  const list = db.reviews.filter((r) => r.toId === userId);
  if (!list.length) return { rating: null, ratingCount: 0 };
  const avg = list.reduce((s, r) => s + r.stars, 0) / list.length;
  return { rating: Math.round(avg * 10) / 10, ratingCount: list.length };
};
const pubUser = (u) => u && { id: u.id, name: u.name, phone: u.phone, car: u.car, ...ratingOf(u.id) };
const fullUser = (u) => ({ id: u.id, email: u.email, name: u.name, phone: u.phone, car: u.car, photo: u.photo, ...ratingOf(u.id) });
const rideDate = (r) => new Date(`${r.date}T${r.time}:00`);
const rideView = (r) => ({ ...r, driver: pubUser(db.users.find((u) => u.id === r.driverId)) });
const fail = (res, msg, code = 400) => res.status(code).json({ error: msg });

// Crée une notification pour un utilisateur (lue par l'app via /notifications).
// title/body sont en français ; `data` permet à l'app de réécrire le texte dans la langue choisie.
const notify = (userId, type, title, body, rideId = null, data = {}) =>
  db.notifications.push({
    id: uid(), userId, type, title, body, rideId, data,
    read: false, delivered: false, createdAt: new Date().toISOString(),
  });
const rideData = (r, extra = {}) => ({ from: r.from, to: r.to, date: r.date, time: r.time, ...extra });

// ---------- Géocodage (OpenStreetMap Nominatim, gratuit) ----------
// Transforme "Ariana" en coordonnées pour la carte. Résultats gardés dans db.geocache.
async function geocode(place) {
  const key = place.trim().toLowerCase();
  if (key in db.geocache) return db.geocache[key];
  const search = async (extra) => {
    const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1${extra}&q=${encodeURIComponent(place)}`;
    const r = await fetch(url, {
      headers: { 'User-Agent': 'CampusCarpool/1.0 (student project)' },
      signal: AbortSignal.timeout(5000),
    });
    const list = await r.json();
    return list[0] ? [+list[0].lat, +list[0].lon] : null;
  };
  try {
    // On cherche d'abord en Tunisie, puis partout
    const result = (await search('&countrycodes=tn')) || (await search(''));
    db.geocache[key] = result;
    return result;
  } catch {
    return null; // pas d'internet : trajet sans carte (on réessaiera plus tard)
  }
}

async function addCoords(ride) {
  if (ride.fromLat != null && ride.toLat != null) return;
  const [a, b] = [await geocode(ride.from), await geocode(ride.to)];
  if (a && b) Object.assign(ride, { fromLat: a[0], fromLng: a[1], toLat: b[0], toLng: b[1] });
}
const nameOf = (id) => (db.users.find((u) => u.id === id) || {}).name || 'Quelqu’un';
const route = (r) => `${r.from} → ${r.to}`;

function auth(req, res, next) {
  const t = (req.headers.authorization || '').replace('Bearer ', '');
  const userId = db.tokens[t];
  const user = db.users.find((u) => u.id === userId);
  if (!user) return fail(res, 'Non authentifié', 401);
  req.user = user;
  next();
}

// ---------- Auth ----------
app.post('/auth/register', (req, res) => {
  const { email, password, name } = req.body;
  if (!email || !password || !name) return fail(res, 'Champs manquants');
  if (!isUniEmail(email)) return fail(res, 'Utilisez votre email universitaire');
  if (password.length < 6) return fail(res, 'Mot de passe : 6 caractères minimum');
  if (db.users.find((u) => u.email === email.toLowerCase())) return fail(res, 'Email déjà utilisé');
  const user = { id: uid(), email: email.toLowerCase(), name, password: hash(password), phone: '', car: { model: '', plate: '' }, photo: null };
  db.users.push(user);
  const token = crypto.randomBytes(24).toString('hex');
  db.tokens[token] = user.id;
  save();
  res.json({ token, user: fullUser(user) });
});

app.post('/auth/login', (req, res) => {
  const { email, password } = req.body;
  const user = db.users.find((u) => u.email === (email || '').toLowerCase());
  if (!user || !checkPwd(password || '', user.password)) return fail(res, 'Email ou mot de passe incorrect', 401);
  const token = crypto.randomBytes(24).toString('hex');
  db.tokens[token] = user.id;
  save();
  res.json({ token, user: fullUser(user) });
});

app.get('/me', auth, (req, res) => res.json(fullUser(req.user)));

app.put('/me', auth, (req, res) => {
  const { name, phone, car, photo } = req.body;
  if (name) req.user.name = name;
  if (phone !== undefined) req.user.phone = phone;
  if (car) req.user.car = { model: car.model || '', plate: car.plate || '' };
  if (photo !== undefined) req.user.photo = photo;
  save();
  res.json(fullUser(req.user));
});

// ---------- Rides ----------
app.post('/rides', auth, async (req, res) => {
  const { from, to, date, time, seats, price } = req.body;
  if (!from || !to || !date || !time || !seats || price === undefined) return fail(res, 'Champs manquants');
  const ride = { id: uid(), driverId: req.user.id, from, to, date, time, seats: +seats, seatsLeft: +seats, price: +price, status: 'open' };
  if (isNaN(rideDate(ride)) || rideDate(ride) < new Date()) return fail(res, 'Date/heure invalide');
  if (ride.seats < 1 || ride.price < 0) return fail(res, 'Places/prix invalides');
  await addCoords(ride);
  db.rides.push(ride);
  save();
  res.json(rideView(ride));
});

// Recherche + filtres : destination, date, prix max, places min
app.get('/rides', auth, (req, res) => {
  const { destination, date, maxPrice, minSeats } = req.query;
  const list = db.rides
    .filter((r) => r.status === 'open' && r.seatsLeft > 0 && rideDate(r) >= new Date() && r.driverId !== req.user.id)
    .filter((r) => !destination || r.to.toLowerCase().includes(destination.toLowerCase()))
    .filter((r) => !date || r.date === date)
    .filter((r) => !maxPrice || r.price <= +maxPrice)
    .filter((r) => !minSeats || r.seatsLeft >= +minSeats)
    .sort((a, b) => rideDate(a) - rideDate(b))
    .map((r) => ({
      ...rideView(r),
      myBooking: (db.bookings.find((b) => b.rideId === r.id && b.passengerId === req.user.id && ['pending', 'accepted'].includes(b.status)) || {}).status || null,
    }));
  res.json(list);
});

app.get('/rides/mine', auth, (req, res) => {
  const list = db.rides
    .filter((r) => r.driverId === req.user.id)
    .sort((a, b) => rideDate(b) - rideDate(a))
    .map((r) => ({
      ...rideView(r),
      bookings: db.bookings.filter((b) => b.rideId === r.id).map((b) => ({
        ...b, passenger: pubUser(db.users.find((u) => u.id === b.passengerId)),
      })),
    }));
  res.json(list);
});

app.post('/rides/:id/cancel', auth, (req, res) => {
  const ride = db.rides.find((r) => r.id === req.params.id && r.driverId === req.user.id);
  if (!ride) return fail(res, 'Trajet introuvable', 404);
  ride.status = 'cancelled';
  db.bookings.filter((b) => b.rideId === ride.id && ['pending', 'accepted'].includes(b.status))
    .forEach((b) => {
      b.status = 'cancelled';
      notify(b.passengerId, 'ride_cancelled', 'Trajet annulé',
        `${req.user.name} a annulé le trajet ${route(ride)} du ${ride.date}.`, ride.id,
        rideData(ride, { name: req.user.name }));
    });
  ride.seatsLeft = ride.seats;
  save();
  res.json({ ok: true });
});

// ---------- Bookings ----------
app.post('/rides/:id/book', auth, (req, res) => {
  const ride = db.rides.find((r) => r.id === req.params.id);
  if (!ride || ride.status !== 'open') return fail(res, 'Trajet indisponible', 404);
  if (ride.driverId === req.user.id) return fail(res, 'Vous ne pouvez pas réserver votre propre trajet');
  if (rideDate(ride) < new Date()) return fail(res, 'Ce trajet est déjà passé');
  if (ride.seatsLeft < 1) return fail(res, 'Plus de places');
  if (db.bookings.find((b) => b.rideId === ride.id && b.passengerId === req.user.id && ['pending', 'accepted'].includes(b.status)))
    return fail(res, 'Vous avez déjà une demande pour ce trajet');
  const booking = { id: uid(), rideId: ride.id, passengerId: req.user.id, status: 'pending', createdAt: new Date().toISOString() };
  db.bookings.push(booking);
  notify(ride.driverId, 'booking_new', 'Nouvelle demande',
    `${req.user.name} demande une place pour ${route(ride)} (${ride.date} ${ride.time}).`, ride.id,
    rideData(ride, { name: req.user.name }));
  save();
  res.json(booking);
});

app.get('/bookings/mine', auth, (req, res) => {
  const list = db.bookings
    .filter((b) => b.passengerId === req.user.id)
    .map((b) => ({ ...b, ride: rideView(db.rides.find((r) => r.id === b.rideId)) }))
    .sort((a, b) => rideDate(b.ride) - rideDate(a.ride));
  res.json(list);
});

// Le conducteur accepte / refuse -> le nombre de places est mis à jour automatiquement
app.post('/bookings/:id/respond', auth, (req, res) => {
  const b = db.bookings.find((x) => x.id === req.params.id);
  const ride = b && db.rides.find((r) => r.id === b.rideId);
  if (!b || ride.driverId !== req.user.id) return fail(res, 'Réservation introuvable', 404);
  if (b.status !== 'pending') return fail(res, 'Demande déjà traitée');
  if (req.body.accept) {
    if (ride.seatsLeft < 1) return fail(res, 'Plus de places disponibles');
    ride.seatsLeft -= 1;
    b.status = 'accepted';
    notify(b.passengerId, 'booking_accepted', 'Réservation acceptée ✅',
      `${req.user.name} a accepté votre demande pour ${route(ride)} (${ride.date} ${ride.time}).`, ride.id,
      rideData(ride, { name: req.user.name }));
  } else {
    b.status = 'declined';
    notify(b.passengerId, 'booking_declined', 'Réservation refusée',
      `${req.user.name} a refusé votre demande pour ${route(ride)}.`, ride.id,
      rideData(ride, { name: req.user.name }));
  }
  save();
  res.json(b);
});

app.post('/bookings/:id/cancel', auth, (req, res) => {
  const b = db.bookings.find((x) => x.id === req.params.id && x.passengerId === req.user.id);
  if (!b || !['pending', 'accepted'].includes(b.status)) return fail(res, 'Réservation introuvable', 404);
  const ride = db.rides.find((r) => r.id === b.rideId);
  if (b.status === 'accepted') ride.seatsLeft += 1;
  b.status = 'cancelled';
  notify(ride.driverId, 'booking_cancelled', 'Réservation annulée',
    `${req.user.name} a annulé sa place pour ${route(ride)} (${ride.date}).`, ride.id,
    rideData(ride, { name: req.user.name }));
  save();
  res.json(b);
});

// ---------- Détails d'un trajet ----------
// Infos complètes + ce que l'utilisateur connecté peut faire (réserver, appeler, noter)
app.get('/rides/:id', auth, async (req, res) => {
  const ride = db.rides.find((r) => r.id === req.params.id);
  if (!ride) return fail(res, 'Trajet introuvable', 404);
  if (ride.fromLat == null) {
    await addCoords(ride); // anciens trajets créés avant la carte
    if (ride.fromLat != null) save();
  }
  const me = req.user.id;
  const isDriver = ride.driverId === me;
  const bookings = db.bookings.filter((b) => b.rideId === ride.id);
  const myBooking = bookings.find((b) => b.passengerId === me && b.status !== 'cancelled' && b.status !== 'declined')
    || bookings.filter((b) => b.passengerId === me).pop() || null;
  const accepted = bookings.filter((b) => b.status === 'accepted');
  const driver = db.users.find((u) => u.id === ride.driverId);
  const finished = ride.status !== 'cancelled' && rideDate(ride) < new Date();

  // Qui puis-je noter ? (après le trajet : conducteur <-> passagers acceptés)
  let rateable = [];
  if (finished) {
    if (isDriver) rateable = accepted.map((b) => b.passengerId);
    else if (myBooking && myBooking.status === 'accepted') rateable = [ride.driverId];
  }
  const alreadyRated = (to) => db.reviews.some((r) => r.rideId === ride.id && r.fromId === me && r.toId === to);

  res.json({
    ...rideView(ride),
    driver: { ...pubUser(driver), photo: driver ? driver.photo : null },
    isDriver,
    finished,
    myBooking,
    // Le conducteur voit toutes les demandes ; les autres ne voient que les passagers acceptés
    bookings: (isDriver ? bookings : accepted).map((b) => ({
      ...b, passenger: pubUser(db.users.find((u) => u.id === b.passengerId)),
    })),
    toRate: rateable.filter((id) => !alreadyRated(id)).map((id) => pubUser(db.users.find((u) => u.id === id))),
  });
});

// ---------- Avis / notes ----------
app.post('/rides/:id/review', auth, (req, res) => {
  const ride = db.rides.find((r) => r.id === req.params.id);
  if (!ride) return fail(res, 'Trajet introuvable', 404);
  const { toId, comment } = req.body;
  const stars = Math.round(+req.body.stars);
  if (!(stars >= 1 && stars <= 5)) return fail(res, 'Note entre 1 et 5');
  if (ride.status === 'cancelled' || rideDate(ride) > new Date()) return fail(res, 'Vous pourrez noter après le trajet');
  const me = req.user.id;
  const wasPassenger = (id) => db.bookings.some((b) => b.rideId === ride.id && b.passengerId === id && b.status === 'accepted');
  const allowed = (ride.driverId === me && wasPassenger(toId)) || (toId === ride.driverId && wasPassenger(me));
  if (!allowed) return fail(res, 'Vous ne pouvez pas noter cette personne pour ce trajet', 403);
  if (db.reviews.some((r) => r.rideId === ride.id && r.fromId === me && r.toId === toId)) return fail(res, 'Avis déjà envoyé');
  const review = {
    id: uid(), rideId: ride.id, fromId: me, toId, stars,
    comment: (comment || '').toString().trim().slice(0, 300), createdAt: new Date().toISOString(),
  };
  db.reviews.push(review);
  notify(toId, 'review', 'Nouvel avis ⭐', `${req.user.name} vous a donné ${stars}/5 pour ${route(ride)}.`, ride.id,
    rideData(ride, { name: req.user.name, stars }));
  save();
  res.json(review);
});

// Profil public d'un utilisateur + ses derniers avis
app.get('/users/:id', auth, (req, res) => {
  const u = db.users.find((x) => x.id === req.params.id);
  if (!u) return fail(res, 'Utilisateur introuvable', 404);
  const reviews = db.reviews.filter((r) => r.toId === u.id)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 20)
    .map((r) => ({ ...r, from: nameOf(r.fromId) }));
  res.json({ ...pubUser(u), photo: u.photo, reviews });
});

// ---------- Notifications ----------
app.get('/notifications', auth, (req, res) => {
  const list = db.notifications.filter((n) => n.userId === req.user.id)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 50);
  res.json(list);
});

// Appelé régulièrement par l'app : nombre de non lues + nouvelles notifications à afficher sur le téléphone
app.get('/notifications/poll', auth, (req, res) => {
  const mine = db.notifications.filter((n) => n.userId === req.user.id);
  const fresh = mine.filter((n) => !n.delivered);
  fresh.forEach((n) => (n.delivered = true));
  if (fresh.length) save();
  res.json({ unread: mine.filter((n) => !n.read).length, fresh });
});

app.post('/notifications/read', auth, (req, res) => {
  db.notifications.filter((n) => n.userId === req.user.id && !n.read).forEach((n) => (n.read = true));
  save();
  res.json({ ok: true });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => console.log(`API sur http://localhost:${PORT}`));
