// Test des règles de sécurité Firestore sur le vrai projet : `npm run test:rules`
// Se connecte avec les comptes de démo via l'API publique (les mêmes règles que l'app)
// et vérifie que les actions permises passent et que les actions interdites sont refusées.
// ⚠️ Modifie quelques données de démo : relancez `npm run seed` ensuite.
const path = require('path');
const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, 'service-account.json'))) });
const P = 'campus-carpool-a1d40';
const KEY = 'AIzaSyBFyMicNi79r3mnfFBaYwVxK4C8UC75haY'; // public web API key (lib/firebase_options.dart)
const DOCS = `projects/${P}/databases/(default)/documents`;
const BASE = `https://firestore.googleapis.com/v1/${DOCS}`;

async function token(email) {
  const r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${KEY}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'demo123', returnSecureToken: true }),
  });
  const j = await r.json();
  if (!j.idToken) throw new Error('login failed ' + email + ' ' + JSON.stringify(j.error));
  return { t: j.idToken, uid: j.localId };
}
const val = (v) => {
  if (v === null) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (Number.isInteger(v)) return { integerValue: String(v) };
  if (typeof v === 'number') return { doubleValue: v };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'object') return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, val(x)])) } };
  return { stringValue: v };
};
const fields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, val(v)]));
const create = (p, data, transforms = []) => ({ update: { name: `${DOCS}/${p}`, fields: fields(data) }, currentDocument: { exists: false }, updateTransforms: transforms });
const overwrite = (p, data) => ({ update: { name: `${DOCS}/${p}`, fields: fields(data) } });
const update = (p, data, transforms = []) => ({ update: { name: `${DOCS}/${p}`, fields: fields(data) }, updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true }, updateTransforms: transforms });
const inc = (field, n) => ({ fieldPath: field, increment: val(n) });
const now = { fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' };
async function commit(user, writes) {
  const r = await fetch(`${BASE}:commit`, { method: 'POST', headers: { Authorization: 'Bearer ' + user.t, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }) });
  return r.status;
}
async function query(user, collection, field, value) {
  const r = await fetch(`${BASE}:runQuery`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + user.t, 'Content-Type': 'application/json' },
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: collection }], where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: val(value) } } } }),
  });
  return r.status;
}
let pass = 0, fail = 0;
const expect = (status, ok, msg) => {
  const good = ok ? status === 200 : status === 403;
  good ? pass++ : fail++;
  console.log(`${good ? '  ✓' : '  ✗'} ${msg} (HTTP ${status})`);
};
const notif = (to, type, rideId) => create(`notifications/rc_${Math.random().toString(36).slice(2)}`,
  { userId: to, type, rideId, data: { name: 'x' }, read: false, pushed: false }, [now]);

(async () => {
  const demo = await token('demo@esprit.univ.tn');
  const youssef = await token('youssef.trabelsi@esprit.univ.tn');
  const sarra = await token('sarra.gharbi@esprit.univ.tn');
  const ines = await token('ines.mansour@esprit.univ.tn');
  const db = admin.firestore();

  console.log('Lecture');
  expect(await query(demo, 'rides', 'status', 'open'), true, 'un utilisateur connecté lit les trajets');
  expect(await query(demo, 'notifications', 'userId', demo.uid), true, 'on lit ses propres notifications');
  expect(await query(demo, 'notifications', 'userId', sarra.uid), false, "on ne lit pas les notifications des autres");

  console.log('Réservation');
  const bId = 'rc_booking';
  expect(await commit(demo, [create(`bookings/${bId}`, { rideId: 'f3', passengerId: demo.uid, driverId: youssef.uid, status: 'pending' }, [now]), notif(youssef.uid, 'booking_new', 'f3')]), true, 'demander une place + prévenir le conducteur');
  expect(await commit(demo, [create('bookings/rc_bad1', { rideId: 'f3', passengerId: demo.uid, driverId: youssef.uid, status: 'accepted' }, [now])]), false, "créer une demande déjà 'acceptée' est refusé");
  expect(await commit(demo, [create('bookings/rc_bad2', { rideId: 'f8', passengerId: demo.uid, driverId: demo.uid, status: 'pending' }, [now])]), false, 'réserver son propre trajet est refusé');
  expect(await commit(sarra, [update(`bookings/${bId}`, { status: 'accepted' })]), false, "un autre que le conducteur ne peut pas accepter");
  expect(await commit(youssef, [update(`bookings/${bId}`, { status: 'accepted' }), update('rides/f3', {}, [inc('seatsLeft', -1)]), notif(demo.uid, 'booking_accepted', 'f3')]), true, 'le conducteur accepte (place en moins + notification)');
  expect(await commit(demo, [update('rides/f3', { seatsLeft: 4 })]), false, "un passager ne peut pas modifier les places d'un trajet");

  console.log('Annulation par le passager');
  expect(await commit(demo, [update(`bookings/${bId}`, { status: 'cancelled' }), update('rides/f3', { lastBooking: bId }, [inc('seatsLeft', 1)]), notif(youssef.uid, 'booking_cancelled', 'f3')]), true, 'le passager annule sa place acceptée et la rend au trajet');

  console.log('Avis');
  const b3 = (await db.collection('bookings').where('rideId', '==', 'p2').where('passengerId', '==', ines.uid).get()).docs[0].id;
  const rid = `p2_${demo.uid}_${ines.uid}`;
  expect(await commit(demo, [
    create(`reviews/${rid}`, { rideId: 'p2', bookingId: b3, fromId: demo.uid, fromName: 'Demo', toId: ines.uid, stars: 5, comment: 'Top' }, [now]),
    update(`users/${ines.uid}`, { lastReview: rid }, [inc('ratingSum', 5), inc('ratingCount', 1)]),
    notif(ines.uid, 'review', 'p2'),
  ]), true, 'le conducteur note sa passagère après le trajet (avis + note moyenne)');
  expect(await commit(demo, [overwrite(`reviews/${rid}`, { rideId: 'p2', bookingId: b3, fromId: demo.uid, fromName: 'Demo', toId: ines.uid, stars: 1, comment: '' })]), false, 'un deuxième avis pour le même trajet est refusé');
  const fb = (await db.collection('bookings').where('rideId', '==', 'f2').where('passengerId', '==', demo.uid).get()).docs[0].id;
  const amira = (await db.collection('users').where('email', '==', 'amira.bensalah@esprit.univ.tn').get()).docs[0].id;
  expect(await commit(demo, [create(`reviews/f2_${demo.uid}_${amira}`, { rideId: 'f2', bookingId: fb, fromId: demo.uid, fromName: 'Demo', toId: amira, stars: 5, comment: '' }, [now])]), false, 'noter avant le trajet est refusé');
  expect(await commit(sarra, [create(`reviews/p2_${sarra.uid}_${demo.uid}`, { rideId: 'p2', bookingId: b3, fromId: sarra.uid, fromName: 'Sarra', toId: demo.uid, stars: 1, comment: '' }, [now])]), false, "quelqu'un qui n'était pas dans le trajet ne peut pas noter");
  expect(await commit(demo, [update(`users/${demo.uid}`, {}, [inc('ratingSum', 50), inc('ratingCount', 10)])]), false, 'modifier sa propre note est refusé');
  expect(await commit(sarra, [update(`users/${demo.uid}`, {}, [inc('ratingSum', 5), inc('ratingCount', 1)])]), false, "augmenter la note de quelqu'un sans avis est refusé");

  console.log('Profil');
  expect(await commit(demo, [update(`users/${demo.uid}`, { phone: '22999999' })]), true, 'modifier son téléphone');
  expect(await commit(sarra, [update(`users/${demo.uid}`, { phone: '00000000' })]), false, "modifier le profil de quelqu'un d'autre est refusé");

  console.log(`\n${pass} réussis, ${fail} échoués`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
