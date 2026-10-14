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
const save = () => fs.writeFileSync(FILE, JSON.stringify(db, null, 2));
const uid = () => crypto.randomBytes(6).toString('hex');
const hash = (p, salt = crypto.randomBytes(8).toString('hex')) =>
  salt + ':' + crypto.scryptSync(p, salt, 32).toString('hex');
const checkPwd = (p, h) => hash(p, h.split(':')[0]) === h;

// Email universitaire : domaine contenant "univ", ou finissant par .edu / .ac.xx (modifiable)
const isUniEmail = (e) =>
  /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) &&
  /(^|\.)(edu|ac)(\.|$)|univ/i.test(e.split('@')[1]);

const pubUser = (u) => u && { id: u.id, name: u.name, phone: u.phone, car: u.car };
const fullUser = (u) => ({ id: u.id, email: u.email, name: u.name, phone: u.phone, car: u.car, photo: u.photo });
const rideDate = (r) => new Date(`${r.date}T${r.time}:00`);
const rideView = (r) => ({ ...r, driver: pubUser(db.users.find((u) => u.id === r.driverId)) });
const fail = (res, msg, code = 400) => res.status(code).json({ error: msg });

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
app.post('/rides', auth, (req, res) => {
  const { from, to, date, time, seats, price } = req.body;
  if (!from || !to || !date || !time || !seats || price === undefined) return fail(res, 'Champs manquants');
  const ride = { id: uid(), driverId: req.user.id, from, to, date, time, seats: +seats, seatsLeft: +seats, price: +price, status: 'open' };
  if (isNaN(rideDate(ride)) || rideDate(ride) < new Date()) return fail(res, 'Date/heure invalide');
  if (ride.seats < 1 || ride.price < 0) return fail(res, 'Places/prix invalides');
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
    .forEach((b) => (b.status = 'cancelled'));
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
  } else b.status = 'declined';
  save();
  res.json(b);
});

app.post('/bookings/:id/cancel', auth, (req, res) => {
  const b = db.bookings.find((x) => x.id === req.params.id && x.passengerId === req.user.id);
  if (!b || !['pending', 'accepted'].includes(b.status)) return fail(res, 'Réservation introuvable', 404);
  if (b.status === 'accepted') db.rides.find((r) => r.id === b.rideId).seatsLeft += 1;
  b.status = 'cancelled';
  save();
  res.json(b);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => console.log(`API sur http://localhost:${PORT}`));
