# Android builds (APK / AAB)

The build definition is [`ci/android-apk.yml`](../ci/android-apk.yml). It has to be installed once
as `.github/workflows/android-apk.yml`, because GitHub only runs workflows from that directory and
the Arena GitHub App is not permitted to write it (see "Install it" below). The build itself runs on
a GitHub-hosted runner, so no local Android Studio/SDK is required to get an APK.

## Install the workflow (one time, ~30 seconds)

Option A - GitHub web UI, no terminal:

1. Open <https://github.com/nuriddinwoo/GloboVerse/new/arena/01a089a3-globoverse?filename=.github/workflows/android-apk.yml>
2. Open [`ci/android-apk.yml`](../ci/android-apk.yml) in another tab, press **Copy raw**, paste it in
   the editor and name the file exactly `android-apk.yml` (the path is already pre-filled).
3. **Commit** to that branch. Actions picks it up and the first run starts immediately.

Option B - terminal (needs `gh` authenticated as you):

```bash
bash ci/install-workflow.sh
```

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
