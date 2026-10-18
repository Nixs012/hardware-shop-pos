# hardware-shop-pos

Flutter-based Android POS for a hardware shop.

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

## Building

```bash
cd app
flutter pub get
flutter build apk --release
```

## Notes

- The app targets `com.shamamo.pos` (namespace in `app/android/app/build.gradle.kts`).
- Keystore: `app/android/key.properties` + `app/android/app/upload-keystore.jks`.
