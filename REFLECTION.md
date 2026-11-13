# Campus Carpool — Project Reflection

This document looks back on how Campus Carpool was built: the main technical decisions and why we made them, the problems we hit and how we solved them, and what we would do differently. For setup and architecture details, see the [README](README.md).

## 1. Where we started and where we ended

| | Start | End |
|---|---|---|
| Backend | Node.js/Express server storing everything in one JSON file (`db.json`) | Firebase: Authentication, Cloud Firestore, security rules, Cloud Messaging |
| Data access | Raw `Map` objects passed between screens | Typed models, repositories per domain, technical services |
| State | `setState` everywhere, static globals | `Provider` with `ChangeNotifier` for shared state |
| Features | Search, post, book, accept/decline, profile | + ride details with map, call/WhatsApp, ratings, real-time and push notifications, ending a ride, FR/EN, dark mode, offline mode |
| Running on a phone | Phone and PC on the same network (or `adb reverse`), backend running on the PC | Any phone with internet; no local server needed |
| Quality | No working tests | 53 Flutter tests, 18 live security-rule checks, `flutter analyze` with 0 issues |

## 2. Key decisions and trade-offs

### Firebase instead of a real database behind Node.js
We considered three options: a SQL database behind our Node server, Strapi (low-code), and Firebase (Backend as a Service). We chose **Firebase** because it solved our two real gaps at once: the app now works **without our PC**, and it gives us **real-time updates**. The cost was rewriting the data layer and learning NoSQL modelling (no joins, so related data is read in parallel).

### Staying on the free plan
Push notifications to a closed app normally need **Cloud Functions**, which require the paid Blaze plan. Instead, we wrote a small **Node.js push server** using the Firebase Admin SDK: it listens for new notifications and sends them through Firebase Cloud Messaging, which is free. The trade-off is that this server must be running for closed-app push; without it, users still get notifications **in real time inside the app**.

### Business rules enforced by the server, not only the app
The app checks rules to show clear messages ("you can't book your own ride"), but anyone could modify an app. So the same rules live in **`firestore.rules`**, which Google's servers enforce: only the driver can accept, seats can't be invented, a review is allowed once, after the ride, between participants only.

### Layered architecture
We split the code into **models → services → repositories → providers → screens**. Screens never touch Firebase. This made the code easier to read, to split between four people, and to test with an in-memory Firestore (`fake_cloud_firestore`). We did not go to a full MVVM (one ViewModel per screen) to avoid a risky rewrite close to the validation; it is a natural next step.

### Notifications store data, not sentences
A notification stores *who, which ride, when*, not a finished sentence. The app (and the push server) write the text in **each user's language**. This is what made French/English notifications possible.

## 3. Problems we hit and how we solved them

| Problem | Cause | Solution |
|---|---|---|
| Phone showed "server unavailable" | The app called `localhost`, which on a phone is the phone itself; then the PC's IP changed and the firewall blocked port 3000 | Server address configurable at build time, `adb reverse` over USB; finally removed entirely by moving to Firebase |
| Builds failed with "not enough space on the disk" | The system drive was almost full | Moved the Android SDK and Gradle cache to another drive; cleaned old build output |
| Build crashed the Java process | The Gradle template asks for up to 8 GB of RAM on a PC that has 8 GB in total | Lowered Gradle's memory limits in `gradle.properties` |
| Every booking was refused by Firebase | In the security rules, a `$(...)` path variable is a single segment, so `doc('rides/' + id)` built a wrong path | Wrote full document paths; found by a script that tests the rules on the real project as real users |
| Test fakes didn't compile | `fake_cloud_firestore` lagged one minor version behind Firestore | Pinned Firestore to the compatible version |
| One file did everything (`api.dart`, 553 lines) | Features were added where it was fastest | Split into services and repositories, with all tests passing before and after |

## 4. What went well
- **Testing early paid off.** The live rules test found a bug that unit tests could not, and the test suite let us restructure the data layer with confidence.
- **Branches and pull requests** let one member migrate to Firebase while others kept adding features, and the merges were clean.
- **Matching the course concepts deliberately** (ListView/GridView, Form + validators, named routes, HTTP, state) made it easy to show where each chapter lives in the code.

## 5. What we would do differently
- **Choose the backend first.** Starting with a JSON file meant rewriting the data layer later. A short comparison at the start would have saved time.
- **Keep the data layer split from day one**, instead of refactoring one large file afterwards.
- **Check the development machines early** (disk space, RAM) before they block builds during a demo week.
- **Write the security rules together with the features**, not after, and test them as we go.

## 6. Next steps
- Full MVVM with one ViewModel per screen.
- An AI assistant (Gemini through Firebase AI Logic) for natural-language search and review summaries.
- Hosting the push server (or moving to Cloud Functions) so push works without a team member's PC.
- iOS version, recurring rides, in-app messaging.

## 7. Personal reflections

Each member adds a few lines: what they built, what they learned, and what was hardest.

- **Baha** — *to complete*
- **Mariem** — *to complete*
- **Chifaa** — *to complete*
- **Aya** — *to complete*
