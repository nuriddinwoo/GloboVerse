#!/usr/bin/env bash
# Provides a release signing key for `flutter build apk --release` / `appbundle`.
#
#  * If the APK_KEYSTORE* repository secrets already exist -> decode them into
#    android/ so this build is signed with the same key as every previous build.
#  * On the very first run -> generate a fresh PKCS12 keystore, persist it as
#    repository Actions secrets (so the key survives and app updates keep
#    working) and use it for this build immediately.
#
# Nothing is ever written to the git tree: android/key.properties and
# *.keystore are gitignored.
set -euo pipefail

KS_DIR="$GITHUB_WORKSPACE/android/keystore"
PROPS="$GITHUB_WORKSPACE/android/key.properties"
KS_FILE="$KS_DIR/release.keystore"
ALIAS="${APK_KEY_ALIAS:-globoverse}"

mkdir -p "$KS_DIR"

rand_password() { openssl rand -hex 16; }

write_props() {
  cat > "$PROPS" <<EOF
storeFile=keystore/release.keystore
storePassword=$1
keyPassword=$2
keyAlias=$3
EOF
  echo "wrote $PROPS"
}

print_fingerprints() {
  local store_pw="$1"
  echo
  echo "=== Signing certificate fingerprints ==="
  echo "Add the SHA-1 (and SHA-256) to Firebase / Google Cloud OAuth client"
  echo "and to Google Play > App signing if you use Google Play."
  keytool -list -v -keystore "$KS_FILE" -storepass "$store_pw" -alias "$ALIAS" 2>/dev/null |
    grep -iE "SHA1:|SHA256:" | sed 's/^[[:space:]]*//' ||
    echo "(could not read fingerprints)"
  echo "========================================"
}

if [ -n "${APK_KEYSTORE_B64:-}" ]; then
  echo "Release keystore found in repository secrets - reusing it."
  printf '%s' "$APK_KEYSTORE_B64" | base64 -d > "$KS_FILE"
  write_props "${APK_STORE_PASSWORD:-}" "${APK_KEY_PASSWORD:-}" "${APK_KEY_ALIAS:-globoverse}"
  print_fingerprints "${APK_STORE_PASSWORD:-}"
  exit 0
fi

echo "No APK_KEYSTORE secret yet - generating a one-time release key."
STORE_PW="$(rand_password)"
KEY_PW="$(rand_password)"

keytool -genkeypair -noprompt -storetype PKCS12 \
  -keystore "$KS_FILE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10950 \
  -storepass "$STORE_PW" -keypass "$KEY_PW" \
  -dname "CN=GloboVerse, OU=Mobile, O=GloboVerse, L=Dushanbe, C=TJ" >/dev/null

write_props "$STORE_PW" "$KEY_PW" "$ALIAS"
print_fingerprints "$STORE_PW"

persist() { # <secret-name> <value>
  if printf '%s' "$2" | gh secret set "$1" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    return 0
  fi
  echo "::warning::could not store $1 in repository secrets"
  return 1
}

ok=1
persist APK_KEYSTORE "$(base64 -w0 < "$KS_FILE")" || ok=0
persist APK_STORE_PASSWORD "$STORE_PW" || ok=0
persist APK_KEY_PASSWORD "$KEY_PW" || ok=0
persist APK_KEY_ALIAS "$ALIAS" || ok=0

if [ "$ok" = "1" ]; then
  echo
  echo "Keystore saved to Settings > Secrets and variables > Actions."
  echo "Every later build reuses it, so app updates install over the old version."
  echo "IMPORTANT: keep those four secrets - deleting them breaks updateability."
else
  echo
  echo "::warning::Keystore NOT persisted. This release APK is signed with a"
  echo "::warning::throwaway key, so future builds cannot update it in place."
  echo "::warning::Grant this workflow 'actions: write' or add the secrets manually."
fi

# NOTE: passwords are deliberately never echoed - run logs and job summaries are
# public on this repository. They only exist in android/key.properties for this job.
if [ "$ok" != "1" ]; then
  echo "Keystore backup: download the 'globoverse-android' artifact is NOT signed-safe;"
  echo "to keep this key, copy android/key.properties from the runner or add the four"
  echo "APK_* secrets manually and re-run."
fi
