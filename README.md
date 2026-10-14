# Campus Carpool

### Your campus. Your route. Your ride.

Campus Carpool is a Flutter app that helps university communities share rides. Find a seat, offer a trip, and manage ride requests in one place. The app talks to a lightweight Node.js/Express API, with project data persisted locally in a JSON file.

> **Project layout:** The Campus Carpool app lives in [`campus_carpool/`](campus_carpool/). Run Flutter commands from that directory. The repository-root `lib/` directory is a separate Flutter starter scaffold.

## ✨ What you can do

- **Join with a university email** — create an account or sign in; registration checks for university-style email domains.
- **Find a ride** — search open trips by destination, date, maximum price, and minimum available seats.
- **Offer a ride** — publish your route, departure time, seat count, and per-seat price.
- **Handle ride requests** — drivers can accept or decline passenger requests; available seats update when a request is accepted.
- **Keep track of plans** — view your offered rides and bookings, split into upcoming trips and history.
- **Stay in control** — cancel your own trip or booking, with seat counts and related booking statuses updated by the API.
- **Set up your profile** — add contact details, vehicle information, and a profile photo.
- **Pick up where you left off** — the Flutter app stores the login token locally and restores the session on launch.
- **Get instant in-app help** — open the Campus Guide from any signed-in tab for quick answers and one-tap shortcuts to the relevant section.

## 🧱 Architecture

```text
Flutter client (campus_carpool/lib)
        │  HTTP + JSON, bearer-token authentication
        ▼
Express API (campus_carpool/backend/server.js)
        │  reads and writes
        ▼
JSON datastore (campus_carpool/backend/db.json)
```

### Flutter client

The client is a Material 3 Flutter app. `main.dart` initializes the API/session and switches between authentication and the signed-in app. The bottom navigation hosts the main feature screens:

| Screen | Responsibility |
| --- | --- |
| `screens/auth_screen.dart` | Sign in and university-email registration |
| `screens/search_screen.dart` | Search/filter rides and request a seat |
| `screens/post_ride_screen.dart` | Publish a ride |
| `screens/my_rides_screen.dart` | Manage driver rides and respond to requests |
| `screens/my_bookings_screen.dart` | Track and cancel passenger bookings |
| `screens/profile_screen.dart` | Edit personal/vehicle details and profile photo |

`api.dart` centralizes HTTP requests, API errors, authentication state, and persisted login tokens. `widgets.dart` contains shared ride/status UI and small presentation helpers.

The Campus Guide is an offline, built-in assistant in `screens/help_chat_screen.dart`. It matches common questions to app-specific instructions and can take users directly to the related tab. It needs no API key, sends no chat messages to the backend, and works without an internet connection.

### API and data

The Express service validates requests, checks bearer tokens, applies ride and booking rules, and reads/writes `backend/db.json`. The file contains `users`, `rides`, `bookings`, and `tokens`. Passwords are stored as salted scrypt hashes; profile and ride responses expose only the user details needed by the client.

This JSON-file backend is intended for local development and demos, not concurrent or production deployment: it has no database transactions, backups, or production-grade operational controls.

## 🚀 Run locally

### Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) with Dart 3.x
- [Node.js](https://nodejs.org/) and npm
- An emulator/simulator or a connected device

### 1. Start the API

From the repository root:

```sh
cd campus_carpool/backend
npm install
npm start
```

The API listens on **port 3000** by default. Keep this terminal running. To use another port, set the `PORT` environment variable before starting the server.

### 2. Prepare and launch the Flutter app

Open a second terminal:

```sh
cd campus_carpool
flutter pub get
flutter run
```

If this checkout does not include platform runner folders inside `campus_carpool/`, generate them once from that directory before launching:

```sh
flutter create .
```

To choose a target explicitly, first check available devices with `flutter devices`, then run for example:

```sh
flutter run -d chrome
```

The same API can be started before launching for Chrome or an iOS simulator; both use `localhost` by default.

## 📡 Connecting a device to the API

The API URL is configured in [`campus_carpool/lib/api.dart`](campus_carpool/lib/api.dart):

| Target | Default API address |
| --- | --- |
| Android emulator | `http://10.0.2.2:3000` |
| Chrome / iOS simulator | `http://localhost:3000` |
| Physical device | Set `Api.base` to your development computer's LAN address, e.g. `http://192.168.1.20:3000` |

For a physical device, make sure it and the development computer are on the same network, the API is listening, and the computer firewall permits connections to port 3000. Android builds may also need cleartext HTTP enabled for local development; use HTTPS for a deployed service.

## 🔌 API at a glance

All endpoints except registration and login require the bearer token returned by authentication.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `POST` | `/auth/register` | Create an account |
| `POST` | `/auth/login` | Sign in |
| `GET` / `PUT` | `/me` | Fetch or update the signed-in profile |
| `GET` / `POST` | `/rides` | Search open rides or publish a ride |
| `GET` | `/rides/mine` | List rides offered by the signed-in driver, including requests |
| `POST` | `/rides/:id/book` | Request a seat |
| `POST` | `/rides/:id/cancel` | Cancel a ride as its driver |
| `GET` | `/bookings/mine` | List the signed-in passenger's bookings |
| `POST` | `/bookings/:id/respond` | Accept or decline a request as the driver |
| `POST` | `/bookings/:id/cancel` | Cancel a booking as its passenger |

Ride search accepts optional `destination`, `date`, `maxPrice`, and `minSeats` query parameters.

## 🗂️ Project map

```text
campus_carpool/
├── lib/
│   ├── main.dart
│   ├── api.dart
│   ├── widgets.dart
│   └── screens/
│       └── help_chat_screen.dart
├── backend/
│   ├── server.js
│   ├── package.json
│   └── db.json
├── pubspec.yaml
└── README.md
```

## 🧪 Useful commands

Run these from `campus_carpool/`:

```sh
flutter analyze
flutter devices
flutter run
```

Run backend from `campus_carpool/backend/`:

```sh
npm start
```

## 🛠️ Built with

- **Flutter / Dart** — cross-platform app UI
- **Node.js + Express** — REST API
- **JSON file storage** — simple local persistence
- **`http`** — client/server communication
- **`shared_preferences`** — local session token persistence
- **`image_picker`** — profile photo selection
