// Serveur de notifications push de Campus Carpool : `npm start`
//
// L'app écrit une notification dans Firestore (collection "notifications") à chaque événement.
// Ce petit serveur écoute ces nouvelles notifications et envoie une vraie notification push
// (Firebase Cloud Messaging) sur le téléphone du destinataire, même quand l'app est fermée.
// FCM est gratuit : pas besoin du forfait Blaze ni de Cloud Functions.
//
// Prérequis : service-account.json (console Firebase > Paramètres du projet > Comptes de service).
const admin = require('firebase-admin');
const path = require('path');

admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, 'service-account.json'))) });
const db = admin.firestore();
const messaging = admin.messaging();

// Textes des notifications (mêmes clés que lib/l10n.dart)
const texts = {
  fr: {
    booking_new: ['Nouvelle demande', '{name} demande une place pour {route} ({date} {time}).'],
    booking_accepted: ['Réservation acceptée ✅', '{name} a accepté votre demande pour {route} ({date} {time}).'],
    booking_declined: ['Réservation refusée', '{name} a refusé votre demande pour {route}.'],
    booking_cancelled: ['Réservation annulée', '{name} a annulé sa place pour {route} ({date}).'],
    ride_cancelled: ['Trajet annulé', '{name} a annulé le trajet {route} du {date}.'],
    ride_ended: ['Trajet terminé', '{name} a terminé le trajet {route} du {date}.'],
    review: ['Nouvel avis ⭐', '{name} vous a donné {stars}/5 pour {route}.'],
    ride_alert: ['Nouveau trajet pour votre alerte 🔔', '{name} propose {route} le {date} à {time} ({price} dt).'],
    ride_alert_series: ['Nouveau trajet pour votre alerte 🔔', '{name} propose {route} {count} fois, à partir du {date} à {time} ({price} dt).'],
  },
  en: {
    booking_new: ['New request', '{name} requested a seat for {route} ({date} {time}).'],
    booking_accepted: ['Booking accepted ✅', '{name} accepted your request for {route} ({date} {time}).'],
    booking_declined: ['Booking declined', '{name} declined your request for {route}.'],
    booking_cancelled: ['Booking cancelled', '{name} cancelled their seat for {route} ({date}).'],
    ride_cancelled: ['Ride cancelled', '{name} cancelled the ride {route} on {date}.'],
    ride_ended: ['Ride completed', '{name} ended the ride {route} on {date}.'],
    review: ['New review ⭐', '{name} gave you {stars}/5 for {route}.'],
    ride_alert: ['New ride for your alert 🔔', '{name} offers {route} on {date} at {time} ({price} dt).'],
    ride_alert_series: ['New ride for your alert 🔔', '{name} offers {route} {count} times, from {date} at {time} ({price} dt).'],
  },
};

function format(n, lang) {
  const d = n.data || {};
  // Alerte sur un trajet régulier : un seul envoi pour toute la série
  const type = n.type === 'ride_alert' && d.count > 1 ? 'ride_alert_series' : n.type;
  const [title, body] = (texts[lang] || texts.fr)[type] || ['Campus Carpool', ''];
  const values = { ...d, route: `${d.from} → ${d.to}` };
  return { title, body: body.replace(/\{(\w+)\}/g, (_, k) => (values[k] ?? '').toString()) };
}

// Envoie une notification push à tous les appareils d'un utilisateur ; retire les jetons expirés.
async function pushTo(userId, label, build) {
  const user = (await db.doc(`users/${userId}`).get()).data() || {};
  const tokens = user.fcmTokens || [];
  if (!tokens.length) {
    console.log(`[push] ${label} -> ${user.name || userId}: aucun appareil enregistré`);
    return;
  }
  const { title, body, data } = build(user);
  const res = await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    android: {
      priority: 'high',
      notification: { channelId: 'carpool_activity', icon: 'ic_stat_notify', color: '#3F51B5' },
    },
  });
  // Jetons expirés (app désinstallée, déconnexion) : on les retire
  const dead = tokens.filter((_, i) => {
    const code = res.responses[i].error?.code;
    return code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token';
  });
  if (dead.length) await db.doc(`users/${userId}`).update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead) });
  console.log(`[push] ${label} -> ${user.name || userId}: ${res.successCount}/${tokens.length} envoyée(s)`);
}

async function send(doc) {
  const n = doc.data();
  await pushTo(n.userId, n.type, (user) => ({
    ...format(n, user.lang),
    data: { rideId: n.rideId || '', type: n.type },
  }));
  await doc.ref.update({ pushed: true });
}

// Messagerie : le titre est le nom de l'expéditeur, le texte est le message
async function sendMessage(doc) {
  const m = doc.data();
  await pushTo(m.to, 'message', () => ({
    title: `💬 ${m.fromName || 'Campus Carpool'}`,
    body: m.text.length > 180 ? m.text.slice(0, 177) + '…' : m.text,
    data: { type: 'message', bookingId: m.bookingId || '', rideId: m.rideId || '' },
  }));
  await doc.ref.update({ pushed: true });
}

db.collection('notifications')
  .where('pushed', '==', false)
  .onSnapshot(
    (snap) => snap.docChanges().forEach((c) => {
      if (c.type === 'added') send(c.doc).catch((e) => console.error('[push] erreur :', e.message));
    }),
    (err) => console.error('[push] écoute impossible :', err.message),
  );

db.collection('messages')
  .where('pushed', '==', false)
  .onSnapshot(
    (snap) => snap.docChanges().forEach((c) => {
      if (c.type === 'added') sendMessage(c.doc).catch((e) => console.error('[push] erreur message :', e.message));
    }),
    (err) => console.error('[push] écoute des messages impossible :', err.message),
  );

console.log('Serveur push démarré : en attente de nouvelles notifications et de messages… (Ctrl+C pour arrêter)');
