# Campus Carpool

### Your campus. Your route. Your ride.

Campus Carpool is a Flutter app that helps university communities share rides. Find a seat, offer a trip, talk to your driver, rate each other after the ride and get notified at every step. The app talks to a lightweight Node.js/Express API, with data persisted in a JSON file.

> **Project layout:** The Campus Carpool app lives in [`campus_carpool/`](campus_carpool/). Run Flutter commands from that directory. The repository-root `lib/` directory is a separate Flutter starter scaffold.

## ✨ Features

**Rides**
- **Join with a university email** — registration accepts university-style domains (`univ`, `.edu`, `.ac.*`).
- **Find a ride** — filter open trips by destination, date, maximum price and minimum free seats.
- **Offer a ride** — a validated form (departure ≠ destination, future date/time, 1–8 seats, positive price).
- **Ride details with a map** — OpenStreetMap view of the route with real road distance and travel time, plus a one-tap "Directions" link to Google Maps.
- **Handle requests** — drivers accept or decline; seats update automatically.

**Trust & communication**
- **Call or WhatsApp** — once a booking is accepted, driver and passenger get *Call* and *WhatsApp* buttons (WhatsApp opens with a pre-written message).
- **Ratings & reviews** — after the ride, driver and passenger rate each other (1–5 ★ + comment). Averages appear on ride cards, ride details and public profiles.
- **Notifications** — bell with an unread badge, a notification list, and Android status-bar notifications for new requests, acceptances, refusals, cancellations and reviews.

**Experience**
- **French / English** — every screen, the assistant and the notifications are translated; the choice is remembered.
- **Dark mode** — light, dark or follow the system.
- **Offline mode** — the last loaded lists are shown from a local cache with an "Offline" banner.
- **Animations** — Hero transition from a ride card to its details, staggered list entrances, `AnimatedList` notifications, shimmer loading skeletons.
- **Profile statistics** — a `GridView` of rides as driver/passenger, seats shared, upcoming trips, rating and reviews.
- **Campus Guide** — an offline assistant that answers common questions and jumps to the right tab.

## 🎓 Course concepts → where to find them

| Course topic | Where it is used |
| --- | --- |
| Cross-platform development | One codebase for Android, web and desktop; `api.dart` picks the server address per platform |
| Everything is a widget / layout widgets | All screens: `Row`, `Column`, `Expanded`, `Stack`, `Wrap`, `Card`, `Container`, custom widgets in `widgets.dart` |
| Lists — `ListView` | `search_screen.dart`, `my_rides_screen.dart`, `my_bookings_screen.dart`, `notifications_screen.dart` (`AnimatedList`) |
| Lists — `GridView` | Statistics grid in `profile_screen.dart` (`GridView.builder`) |
| Forms — `Form`, `TextFormField`, validators | `post_ride_screen.dart`, `profile_screen.dart`; rules in `validators.dart` (unit-tested) |
| Navigation — named routes & `Navigator` | `routes.dart` (`routes:`, `onGenerateRoute` with arguments, `onUnknownRoute`), `Navigator.pushNamed` |
| External APIs — `http` | `api.dart` (REST + JSON, bearer token, timeout, offline cache); OSRM routing in `widgets/ride_map.dart` |
| State management | `provider` package: `AuthProvider`, `NotificationsProvider`, `SettingsProvider`, `L10n` |

## 🧱 Architecture

```text
Flutter client (campus_carpool/lib)
  screens/      UI (one file per screen)
  providers/    shared state with Provider (session, notifications, settings)
  models.dart   typed models: AppUser, Ride, Booking, RideDetails, Review, AppNotification
  api.dart      HTTP service (package http) + offline cache
        │  HTTP + JSON, bearer-token authentication
        ▼
Express API (campus_carpool/backend/server.js)
        │  reads and writes            │  geocoding (OpenStreetMap Nominatim, cached)
        ▼                              ▼
JSON datastore (backend/db.json)   ride coordinates for the map
```

- **Models** — every JSON response is converted with `fromJson` into a typed Dart object, so screens use `ride.price` instead of `ride['price']`.
- **Providers** — `AuthProvider` (current user, login/logout, profile), `NotificationsProvider` (polls the API every 15 s, unread badge, Android notifications), `SettingsProvider` (theme), `L10n` (language). Screens rebuild automatically with `context.watch`.
- **Notifications** are created by the API on each event and fetched by the app. They show while the app is open or in the background; push notifications to a fully closed app would require Firebase Cloud Messaging.
- **Storage** — the JSON-file backend is meant for development and demos (no transactions or production controls).

## 🚀 Run locally

### Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) with Dart 3.x
- [Node.js](https://nodejs.org/) 18+ and npm
- An Android phone (USB debugging on), an emulator, or Chrome

### 1. Start the API (with demo data)

```sh
cd campus_carpool/backend
npm install
npm run seed     # optional: realistic demo users, rides, bookings and reviews
npm start        # API on http://localhost:3000
```

`npm run seed` backs up the current `db.json` to `db.backup-<date>.json` first.

**Demo accounts** (password `demo123`): `demo@esprit.univ.tn`, `amira.bensalah@esprit.univ.tn`, `youssef.trabelsi@esprit.univ.tn`, `sarra.gharbi@esprit.univ.tn`, `mehdi.jaziri@esprit.univ.tn`, `ines.mansour@esprit.univ.tn`.

### 2. Run the app

```sh
cd campus_carpool
flutter pub get
```

| Target | Command |
| --- | --- |
| Android phone over **USB** (simplest) | `adb reverse tcp:3000 tcp:3000` then `flutter run --dart-define=API_HOST=127.0.0.1` |
| Android phone over **Wi-Fi** | `flutter run --dart-define=API_HOST=<your PC's IP>` (same Wi-Fi, firewall allows port 3000) |
| Android emulator | `flutter run --dart-define=API_HOST=10.0.2.2` |
| Chrome | `flutter run -d chrome` |

**Tip for the demo:** run the app on a phone *and* in Chrome, log in with two different demo accounts, then request a seat on one and watch the notification arrive on the other.

### 3. Build an installable APK

```sh
flutter build apk --release --dart-define=API_HOST=<your PC's IP>
# -> build/app/outputs/flutter-apk/app-release.apk
```

## 🔌 API at a glance

All endpoints except registration and login require the bearer token returned by authentication.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `POST` | `/auth/register`, `/auth/login` | Create an account / sign in |
| `GET` / `PUT` | `/me` | Fetch or update the signed-in profile (includes rating) |
| `GET` | `/users/:id` | Public profile with rating and latest reviews |
| `GET` / `POST` | `/rides` | Search open rides (`destination`, `date`, `maxPrice`, `minSeats`) / publish a ride |
| `GET` | `/rides/mine` | Rides offered by the signed-in driver, with requests |
| `GET` | `/rides/:id` | Ride details: driver, passengers, coordinates, my booking, who I can rate |
| `POST` | `/rides/:id/book` · `/rides/:id/cancel` | Request a seat · cancel a ride (driver) |
| `POST` | `/rides/:id/review` | Rate the driver or a passenger after the ride |
| `GET` | `/bookings/mine` | The signed-in passenger's bookings |
| `POST` | `/bookings/:id/respond` · `/bookings/:id/cancel` | Accept/decline (driver) · cancel (passenger) |
| `GET` | `/notifications` · `/notifications/poll` | Notification list · unread count + new notifications |
| `POST` | `/notifications/read` | Mark all as read |

## 🧪 Tests & quality

```sh
cd campus_carpool
flutter analyze        # 0 issues (flutter_lints)
flutter test           # unit + widget tests

cd backend
npm test               # API tests on a temporary copy of the data
```

| Test file | What it checks |
| --- | --- |
| `test/validators_test.dart` | Every form rule (places, date/time, seats, price, phone, plate) |
| `test/models_test.dart` | JSON → model conversion and computed properties, profile statistics |
| `test/l10n_test.dart` | Every text exists in FR **and** EN, every `context.tr('…')` has a translation, notifications are translated |
| `test/widget_test.dart` | Forms show validation errors (FR/EN), named routes, ride details + booking against a mocked API, offline error |
| `test/app_flow_test.dart` | Full signed-in journey: all tabs, notifications, dark mode, language switch |
| `backend/test.js` | Demo data, booking flow, notifications, ride details permissions, reviews rules, cancellations, auth |

## 🗂️ Project map

```text
campus_carpool/
├── lib/
│   ├── main.dart              # providers, themes, named routes
│   ├── api.dart               # HTTP service + offline cache
│   ├── models.dart            # typed models
│   ├── routes.dart            # named routes
│   ├── validators.dart        # form rules
│   ├── l10n.dart              # FR / EN texts
│   ├── widgets.dart           # shared widgets, animations, skeletons
│   ├── widgets/ride_map.dart  # OpenStreetMap + route
│   ├── providers/             # auth, notifications, settings
│   └── screens/               # one file per screen
├── test/                      # Flutter tests
├── backend/
│   ├── server.js              # Express API
│   ├── seed.js                # demo data (npm run seed)
│   ├── test.js                # API tests (npm test)
│   └── db.json                # data (not committed)
└── pubspec.yaml
```

## 🛠️ Built with

- **Flutter / Dart** — cross-platform UI (Material 3, light & dark themes)
- **provider** — state management
- **http** — REST client · **shared_preferences** — session, settings and offline cache
- **flutter_map + latlong2** — OpenStreetMap maps · **OSRM** — road routing · **Nominatim** — geocoding
- **flutter_local_notifications** — Android notifications · **url_launcher** — call, WhatsApp, directions
- **image_picker** — profile photo · **flutter_launcher_icons** — app icon
- **Node.js + Express** — REST API · **JSON file storage**
