# Campus Carpool

### Your campus. Your route. Your ride.

Campus Carpool is a Flutter app that helps university communities share rides. Find a seat, offer a trip, talk to your driver, rate each other after the ride and get notified at every step. It runs on **Firebase**: Authentication for accounts, Cloud Firestore for real-time data, security rules for the business logic, and Cloud Messaging for push notifications.

> **Project layout:** The Campus Carpool app lives in [`campus_carpool/`](campus_carpool/). Run Flutter commands from that directory. The repository-root `lib/` directory is a separate Flutter starter scaffold.

## ✨ Features

**Rides**
- **Join with a university email** — Firebase Authentication; only university-style domains (`univ`, `.edu`, `.ac.*`) can create a profile (checked in the app and in the security rules).
- **Find a ride** — filter open trips by destination, date, maximum price and minimum free seats.
- **Offer a ride** — a validated form (departure ≠ destination, future date/time, 1–8 seats, positive price).
- **Ride details with a map** — OpenStreetMap view of the route with real road distance and travel time, plus a one-tap "Directions" link to Google Maps.
- **Handle requests** — drivers accept or decline; seats update automatically in a Firestore transaction.

**Trust & communication**
- **Call or WhatsApp** — once a booking is accepted, driver and passenger get *Call* and *WhatsApp* buttons.
- **Ratings & reviews** — after the ride, driver and passenger rate each other (1–5 ★ + comment), once per ride.
- **Real-time notifications** — the bell badge updates instantly (Firestore listener); Android notifications while the app is open, and **push notifications when it is closed** (Firebase Cloud Messaging through the free push server).

**Experience**
- **French / English**, **dark mode**, **offline mode** (Firestore local cache + "Offline" banner).
- **Animations** — Hero transition, staggered lists, `AnimatedList`, shimmer skeletons.
- **Profile statistics** (`GridView`) and an offline **Campus Guide** assistant.

## 🎓 Course concepts → where to find them

| Course topic | Where it is used |
| --- | --- |
| Cross-platform development | One codebase for Android and web, configured for both in `firebase_options.dart` |
| Everything is a widget / layout widgets | All screens: `Row`, `Column`, `Expanded`, `Stack`, `Wrap`, `Card`, `Container`, custom widgets in `widgets.dart` |
| Lists — `ListView` | `search_screen.dart`, `my_rides_screen.dart`, `my_bookings_screen.dart`, `notifications_screen.dart` (`AnimatedList`) |
| Lists — `GridView` | Statistics grid in `profile_screen.dart` (`GridView.builder`) |
| Forms — `Form`, `TextFormField`, validators | `post_ride_screen.dart`, `profile_screen.dart`; rules in `validators.dart` (unit-tested) |
| Navigation — named routes & `Navigator` | `routes.dart` (`routes:`, `onGenerateRoute` with arguments, `onUnknownRoute`), `Navigator.pushNamed` |
| External APIs | Firebase (Auth, Firestore, Messaging) in `api.dart` and `providers/`; `http` for OpenStreetMap geocoding and OSRM routing |
| State management | `provider` package: `AuthProvider`, `NotificationsProvider`, `SettingsProvider`, `L10n` |

## 🧱 Architecture

```text
Flutter app (campus_carpool/lib)
  screens/     UI (one file per screen)
  providers/   shared state: AuthProvider (Firebase Auth), NotificationsProvider (Firestore listener + FCM), SettingsProvider
  models.dart  typed models
  api.dart     all Firestore reads/writes (batches and transactions)
        │
        ▼
Firebase project (campus-carpool-a1d40, free Spark plan)
  Authentication    email + password
  Cloud Firestore   users · rides · bookings · reviews · notifications
  firestore.rules   who can do what (enforced by Google's servers)
  Cloud Messaging   push notifications
        ▲
        │  listens to new notifications, sends the push (firebase-admin)
push-server/ (Node.js, runs on your PC or any free host)
```

**Firestore collections**

| Collection | Content | Who can write |
| --- | --- | --- |
| `users/{uid}` | name, email, phone, car, photo, `ratingSum` / `ratingCount`, `fcmTokens`, `lang` | The user (profile); a reviewer can only add their rating |
| `rides/{id}` | route, date/time, seats, price, status, coordinates | The driver; a passenger can only give back their seat |
| `bookings/{id}` | ride, passenger, driver, status | The passenger creates/cancels; the driver accepts/declines |
| `reviews/{ride_from_to}` | stars, comment, author | Only someone who shared that ride, after it, once |
| `notifications/{id}` | recipient, type, data (name, route, date…), read, pushed | Created for someone else; only the recipient reads them |

**Why a push server?** Pushing to a closed app normally needs Cloud Functions, which require the paid Blaze plan. Sending through FCM is free, so a small Node.js process (`push-server/index.js`) listens to new notifications with the Admin SDK and sends them. While it is not running, users still get notifications in real time inside the app.

## 🚀 Run locally

### Requirements
- Flutter SDK (Dart 3.x), Node.js 18+
- Access to the Firebase project `campus-carpool-a1d40`
- `push-server/service-account.json` — Firebase console › Project settings › Service accounts › *Generate new private key* (secret, never committed)

### 1. Demo data (once)
```sh
cd campus_carpool/push-server
npm install
npm run seed        # recreates the demo accounts, rides, bookings and reviews
```
**Demo accounts** (password `demo123`): `demo@esprit.univ.tn`, `amira.bensalah@esprit.univ.tn`, `youssef.trabelsi@esprit.univ.tn`, `sarra.gharbi@esprit.univ.tn`, `mehdi.jaziri@esprit.univ.tn`, `ines.mansour@esprit.univ.tn`.

### 2. Push server (for notifications when the app is closed)
```sh
cd campus_carpool/push-server
npm start
```

### 3. The app
```sh
cd campus_carpool
flutter pub get
flutter run -d chrome          # web
flutter run -d <device-id>     # Android phone (USB debugging) — no server address or adb reverse needed
```
The app talks directly to Firebase over the internet, so any phone or browser with internet works, on any network.

### Deploy rule changes
```sh
firebase deploy --only firestore:rules
```

## 🧪 Tests & quality

```sh
cd campus_carpool
flutter analyze            # 0 issues (flutter_lints)
flutter test               # 48 tests, Firestore simulated in memory (fake_cloud_firestore)

cd push-server
npm run test:rules         # 18 checks of firestore.rules on the real project (then: npm run seed)
```

| Test file | What it checks |
| --- | --- |
| `test/api_test.dart` | Booking, accepting, cancelling, ratings, notifications and permissions on an in-memory Firestore |
| `test/validators_test.dart` | Every form rule |
| `test/models_test.dart` | JSON → typed models, computed properties, statistics |
| `test/l10n_test.dart` | Every text exists in FR and EN, every `context.tr('…')` has a translation |
| `test/widget_test.dart` | Forms (FR/EN), named routes, ride details and booking |
| `test/app_flow_test.dart` | Full signed-in journey: tabs, real-time notification, dark mode, language |
| `push-server/rules-test.js` | Allowed actions pass and forbidden ones are refused by the live security rules |

## 🗂️ Project map

```text
campus_carpool/
├── lib/
│   ├── main.dart               # Firebase init, providers, themes, named routes
│   ├── firebase_options.dart   # generated by flutterfire configure
│   ├── api.dart                # Firestore data layer
│   ├── models.dart  routes.dart  validators.dart  l10n.dart  widgets.dart
│   ├── widgets/ride_map.dart   # OpenStreetMap + route
│   ├── providers/              # auth, notifications, settings
│   └── screens/
├── test/
├── firestore.rules             # security rules
├── firebase.json  .firebaserc  # Firebase CLI configuration
├── push-server/                # push sender, demo data, rules tests (Node.js + firebase-admin)
└── pubspec.yaml
```

## 🛠️ Built with
- **Flutter / Dart**, **provider**
- **Firebase**: firebase_auth, cloud_firestore, firebase_messaging; firebase-admin (push server)
- **flutter_map + latlong2** (OpenStreetMap), **OSRM** routing, **Nominatim** geocoding, **http**
- **flutter_local_notifications**, **url_launcher**, **image_picker**, **shared_preferences**
- Tests: **flutter_test**, **fake_cloud_firestore**
