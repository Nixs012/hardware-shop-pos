# hardware-shop-pos

Flutter-based Android & Web (Chrome) POS for hardware shops.

## Branches

| Branch | Description |
|--------|-------------|
| `main` | Production branch — single-shop, existing data model |
| `feature/accounts` | Multi-shop account system — any new shop can sign up |

---

## Firebase / Kotlin / Gradle

The Android toolchain (Kotlin 2.2.20, Gradle 8.14, AGP 8.12) is pinned by the
current Flutter SDK and JDK 17 in this environment. The Firebase Flutter plugins
are matched to that toolchain.

> **Do not upgrade Firebase or Kotlin packages without running a full release build on a clean checkout.**
> Major version jumps in `firebase_core`, `firebase_auth`, `cloud_firestore`,
> `kotlin`, Gradle, or AGP can introduce Kotlin metadata mismatches
> (e.g. `Module was compiled with an incompatible version of Kotlin`) and
> `PigeonParser` / `FlutterFirebaseAuthUser` compile errors that only surface
> during `flutter build apk --release`.

---

## Running (feature/accounts branch)

### Prerequisites
- Flutter SDK installed and on PATH
- Firebase project configured in `app/lib/firebase_options.dart`
- Firestore rules and indexes deployed (see below)

### Android
```bash
git checkout feature/accounts
cd app
flutter pub get
flutter run                      # attach a device or start emulator first
# or release APK:
flutter build apk --release
```

### Chrome (Web)
```bash
git checkout feature/accounts
cd app
flutter pub get
flutter run -d chrome
```

### Tests
```bash
cd app
flutter test                     # runs all 72 unit + widget tests
```

---

## Multi-Shop Account Flows

### Admin — Create a New Shop
1. Open the app → tap **"Create Shop Account (Admin)"**
2. Fill in: full name, email, password (×2), shop name, address, phone, receipt
   footer, and paper size.
3. Tap **"Create Shop"** — your Firebase account, `shops/{shopId}` document,
   and `users/{uid}` lookup doc are all written in one batch.
4. A **join code** (6-character alphanumeric) is generated and shown in
   Settings → Staff & Access.

### Cashier — Join an Existing Shop
1. Open the app → tap **"Join as Cashier with Join Code"**
2. Enter the join code from the admin, plus your name, email, and password.
3. Tap **"Join Store"** — account is created and scoped to that shop immediately.

### Login (any role)
- Tap **"Log In"** → enter email and password.
- Forgot password → tap the link → reset email is sent via Firebase Auth.

---

## Building

```bash
cd app
flutter pub get
flutter build apk --release
```

## Notes

- The app targets `com.shamamo.pos` (namespace in `app/android/app/build.gradle.kts`).
- Keystore: `app/android/key.properties` + `app/android/app/upload-keystore.jks`.

---

## Firestore Indexes & Rules

All shop data lives under `shops/{shopId}/...`. Security rules ensure each user
can only access their own shop's data.

- `firestore.indexes.json` — composite indexes.
- `app/firestore.rules` — security rules (referenced by `firebase.json`).

Deploy indexes:
```bash
firebase deploy --only firestore:indexes --project shamamo-pos
```

Deploy rules:
```bash
firebase deploy --only firestore:rules --project shamamo-pos
```
