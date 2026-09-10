# Android builds (APK / AAB)

Everything here is automated by [`.github/workflows/android-apk.yml`](../.github/workflows/android-apk.yml).
The build runs on a GitHub-hosted runner, so no local Android SDK is required to get an APK.

## Get the finished files

* **Releases page (permanent link):** <https://github.com/nuriddinwoo/GloboVerse/releases/tag/android-latest>
  * `GloboVerse-debug.apk` — quick install on your phone, includes debug assertions.
  * `GloboVerse-release.apk` — signed, optimized, side-loadable.
  * `GloboVerse-release.aab` — the only format Google Play accepts.
  * `checksums.txt` — `sha256sum` of the files above.
* The same files are also in the workflow run under **Artifacts** (`globoverse-android`).

Trigger a build any time from **Actions → Android build (APK + AAB) → Run workflow**.
The form has optional fields for `GLOBOVERSE_DISCOVERY_API_URL`, `GLOBOVERSE_CHAT_API_URL`,
`GLOBOVERSE_BILLING_API_URL` and `TRANSLATION_API_URL`. Left empty, the app builds and runs
in its documented on-device preview mode (GloboGuide chat, sample discovery catalog,
offline translation preview, purchases fail closed).

## Signing key

`.github/scripts/ensure-keystore.sh` creates a PKCS12 keystore on the first run and stores it
as four repository secrets — `APK_KEYSTORE`, `APK_STORE_PASSWORD`, `APK_KEY_PASSWORD`,
`APK_KEY_ALIAS` — so every later build reuses the *same* certificate and users can update the
app instead of uninstalling it.

* Never delete those four secrets.
* `android/key.properties` and `*.keystore` stay gitignored; nothing is committed.
* The run log prints the certificate **SHA-1 / SHA-256** fingerprints. Those are the values to
  paste into Firebase / Google Cloud (for Google sign-in) and into Google Play → App signing.
* For Google Play you should also enable *Play App Signing* and register this upload key.

## Local build (optional)

```bash
flutter pub get
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # build/app/outputs/bundle/release/app-release.aab
```

To sign locally, put the same values in `android/key.properties`:

```properties
storeFile=keystore/release.keystore
storePassword=...
keyPassword=...
keyAlias=globoverse
```

## iOS

`.ipa` files cannot be produced without Apple certificate/profile material, so they are not part
of this workflow. See [build_ios.md](build_ios.md) for what is needed (Apple ID + team, or a
free 7-day sideload via Xcode).
