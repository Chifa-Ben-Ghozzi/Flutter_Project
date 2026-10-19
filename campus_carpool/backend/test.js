// Tests de l'API : `npm test`
// Lance le serveur sur une COPIE temporaire (port 3999) : votre db.json n'est jamais modifié.
const { spawn, execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PORT = 3999;
const base = `http://localhost:${PORT}`;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'carpool-test-'));
fs.copyFileSync(path.join(__dirname, 'server.js'), path.join(dir, 'server.js'));
fs.copyFileSync(path.join(__dirname, 'seed.js'), path.join(dir, 'seed.js'));
const env = { ...process.env, PORT: String(PORT), NODE_PATH: path.join(__dirname, 'node_modules') };

let srv;
const start = () => new Promise((ok, ko) => {
  srv = spawn(process.execPath, ['server.js'], { cwd: dir, env });
  srv.stdout.once('data', () => ok());
  srv.stderr.on('data', (d) => process.stderr.write(d));
  srv.once('exit', (code) => code && ko(new Error('server exited ' + code)));
});
const stop = () => new Promise((ok) => { srv.once('exit', ok); srv.kill(); });
const dbFile = path.join(dir, 'db.json');
const editDb = (fn) => { const db = JSON.parse(fs.readFileSync(dbFile)); fn(db); fs.writeFileSync(dbFile, JSON.stringify(db)); };

const req = async (method, p, token, body) => {
  const r = await fetch(base + p, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: body && JSON.stringify(body),
  });
  return { s: r.status, d: await r.json() };
};
let passed = 0, failed = 0;
const check = (cond, msg) => { cond ? passed++ : failed++; console.log((cond ? '  ✓ ' : '  ✗ ') + msg); };
const login = async (email) => (await req('POST', '/auth/login', null, { email, password: 'demo123' })).d.token;

(async () => {
  // Jeu de données de démonstration (comptes avec mot de passe demo123, lieux avec coordonnées)
  execFileSync(process.execPath, ['seed.js'], { cwd: dir });
  await start();

  console.log('Données de démo');
  const demo = await login('demo@esprit.univ.tn');
  check(!!demo, 'connexion du compte demo');
  const me = (await req('GET', '/me', demo)).d;
  check(me.rating > 0 && me.ratingCount >= 3, `le compte demo a une note (${me.rating}, ${me.ratingCount} avis)`);
  const search = (await req('GET', '/rides', demo)).d;
  check(search.length >= 4 && search.every((r) => r.driverId !== me.id), 'recherche : trajets des autres uniquement');
  check(search.every((r) => r.fromLat != null), 'les trajets de démo ont des coordonnées (carte)');

  console.log('Réservation + notifications');
  const amira = await login('amira.bensalah@esprit.univ.tn');
  const ines = await login('ines.mansour@esprit.univ.tn');
  const tomorrow = new Date(Date.now() + 864e5).toISOString().slice(0, 10);
  const created = await req('POST', '/rides', amira, { from: 'Ariana', to: 'La Marsa', date: tomorrow, time: '09:00', seats: 2, price: 3 });
  check(created.s === 200 && created.d.fromLat != null, 'nouveau trajet géocodé (cache, sans internet)');
  const ride = created.d;
  await req('GET', '/notifications/poll', amira); // vide la file
  const bk = (await req('POST', `/rides/${ride.id}/book`, ines)).d;
  let p = (await req('GET', '/notifications/poll', amira)).d;
  check(p.fresh.length === 1 && p.fresh[0].type === 'booking_new', 'conducteur notifié de la demande');
  check(p.fresh[0].data.name === 'Ines Mansour' && p.fresh[0].data.from === 'Ariana', 'notification avec données (traduisible)');
  check((await req('GET', '/notifications/poll', amira)).d.fresh.length === 0, 'chaque notification est livrée une seule fois');
  check((await req('POST', `/rides/${ride.id}/book`, ines)).s === 400, 'double demande refusée');
  await req('POST', `/bookings/${bk.id}/respond`, amira, { accept: true });
  p = (await req('GET', '/notifications/poll', ines)).d;
  check(p.fresh.some((n) => n.type === 'booking_accepted'), 'passager notifié de l\'acceptation');

  console.log('Détails du trajet');
  let d = (await req('GET', `/rides/${ride.id}`, ines)).d;
  check(d.myBooking.status === 'accepted' && d.seatsLeft === 1, 'passager accepté, une place en moins');
  check(!d.isDriver && !d.finished && d.toRate.length === 0, 'pas de note avant le trajet');
  check((await req('POST', `/rides/${ride.id}/review`, ines, { toId: ride.driverId, stars: 5 })).s === 400, 'avis refusé avant le trajet');
  const dDriver = (await req('GET', `/rides/${ride.id}`, amira)).d;
  check(dDriver.isDriver && dDriver.bookings.length === 1, 'le conducteur voit les demandes');
  const sarra = await login('sarra.gharbi@esprit.univ.tn');
  const dOther = (await req('GET', `/rides/${ride.id}`, sarra)).d;
  check(dOther.myBooking === null && dOther.bookings.every((b) => b.status === 'accepted'), 'un autre utilisateur ne voit que les passagers acceptés');

  console.log('Avis après le trajet');
  await stop();
  editDb((db) => { db.rides.find((r) => r.id === ride.id).date = '2020-01-01'; });
  await start();
  d = (await req('GET', `/rides/${ride.id}`, ines)).d;
  check(d.finished && d.toRate.length === 1, 'le passager peut noter le conducteur');
  check((await req('POST', `/rides/${ride.id}/review`, ines, { toId: ride.driverId, stars: 9 })).s === 400, 'note hors 1..5 refusée');
  check((await req('POST', `/rides/${ride.id}/review`, ines, { toId: ride.driverId, stars: 4, comment: 'Ponctuelle' })).s === 200, 'avis accepté');
  check((await req('POST', `/rides/${ride.id}/review`, ines, { toId: ride.driverId, stars: 4 })).s === 400, 'avis en double refusé');
  check((await req('POST', `/rides/${ride.id}/review`, sarra, { toId: ride.driverId, stars: 1 })).s === 403, 'un non-passager ne peut pas noter');
  const pub = (await req('GET', `/users/${ride.driverId}`, sarra)).d;
  check(pub.reviews.some((r) => r.comment === 'Ponctuelle' && r.from === 'Ines Mansour'), 'avis visible sur le profil public');
  check((await req('GET', `/rides/${ride.id}`, ines)).d.toRate.length === 0, 'plus rien à noter après l\'avis');

  console.log('Annulations');
  const r2 = (await req('POST', '/rides', amira, { from: 'Ariana', to: 'Lac 2', date: tomorrow, time: '10:00', seats: 2, price: 3 })).d;
  const b2 = (await req('POST', `/rides/${r2.id}/book`, ines)).d;
  await req('POST', `/bookings/${b2.id}/respond`, amira, { accept: true });
  await req('GET', '/notifications/poll', ines);
  await req('POST', `/rides/${r2.id}/cancel`, amira);
  p = (await req('GET', '/notifications/poll', ines)).d;
  check(p.fresh.some((n) => n.type === 'ride_cancelled'), 'passager prévenu de l\'annulation du trajet');
  await req('POST', '/notifications/read', ines);
  check((await req('GET', '/notifications/poll', ines)).d.unread === 0, 'tout marquer comme lu');
  check((await req('GET', '/rides', null)).s === 401, 'sans connexion : 401');

  await stop();
  fs.rmSync(dir, { recursive: true, force: true });
  console.log(`\n${passed} réussis, ${failed} échoués`);
  process.exit(failed ? 1 : 0);
})().catch(async (e) => {
  console.error(e);
  if (srv) srv.kill();
  process.exit(1);
});
