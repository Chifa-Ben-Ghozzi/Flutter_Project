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
    review: ['Nouvel avis ⭐', '{name} vous a donné {stars}/5 pour {route}.'],
  },
  en: {
    booking_new: ['New request', '{name} requested a seat for {route} ({date} {time}).'],
    booking_accepted: ['Booking accepted ✅', '{name} accepted your request for {route} ({date} {time}).'],
    booking_declined: ['Booking declined', '{name} declined your request for {route}.'],
    booking_cancelled: ['Booking cancelled', '{name} cancelled their seat for {route} ({date}).'],
    ride_cancelled: ['Ride cancelled', '{name} cancelled the ride {route} on {date}.'],
    review: ['New review ⭐', '{name} gave you {stars}/5 for {route}.'],
  },
};

function format(n, lang) {
  const [title, body] = (texts[lang] || texts.fr)[n.type] || ['Campus Carpool', ''];
  const d = n.data || {};
  const values = { ...d, route: `${d.from} → ${d.to}` };
  return { title, body: body.replace(/\{(\w+)\}/g, (_, k) => (values[k] ?? '').toString()) };
}

async function send(doc) {
  const n = doc.data();
  const user = (await db.doc(`users/${n.userId}`).get()).data() || {};
  const tokens = user.fcmTokens || [];
  if (tokens.length) {
    const { title, body } = format(n, user.lang);
    const res = await messaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { rideId: n.rideId || '', type: n.type },
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
    if (dead.length) await db.doc(`users/${n.userId}`).update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead) });
    console.log(`[push] ${n.type} -> ${user.name || n.userId}: ${res.successCount}/${tokens.length} envoyée(s)`);
  } else {
    console.log(`[push] ${n.type} -> ${user.name || n.userId}: aucun appareil enregistré`);
  }
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

console.log('Serveur push démarré : en attente de nouvelles notifications… (Ctrl+C pour arrêter)');
