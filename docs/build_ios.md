# iOS build (.ipa)

An `.ipa` is always code-signed, so it cannot be produced from a repository alone. A macOS
runner (GitHub-hosted `macos-latest`) can compile the app, but signing needs material only the
account owner can create.

## What is needed from the Apple account owner

1. Apple ID enrolled in the Apple Developer Program (individual $99/yr, or free personal team).
2. An iOS Distribution certificate + provisioning profile for `com.globoverse.app`, exported as
   `distribution.p12` plus the profile `.mobileprovision`.
3. Bundle id, version and Privacy "Export Compliance" answer — already `com.globoverse.app` here.

Recommended secret layout for a CI workflow: `IOS_CERT_P12` (base64), `IOS_CERT_PASSWORD`,
`IOS_PROFILE` (base64). Then:

```bash
flutter build ipa --release --export-method ad-hoc   # or app-store
# output: build/ios/ipa/globoverse.ipa
```

## Without a paid account

`flutter build ios --release --no-codesign` produces a `.app` that must still be signed on a Mac
with your own Apple ID (Xcode > Signing & Capabilities, 7-day sideload). No CI can skip this step.

## Google sign-in / push

Nothing in this repository uses Firebase: `pubspec.yaml` has no `google_sign_in` or
`firebase_auth`, there is no `google-services.json`, and `AuthService` is a local onboarding
gate. Google sign-in is therefore a feature to implement, not a flag to switch on.
