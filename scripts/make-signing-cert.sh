#!/bin/bash
# Create the self-signed "PrismPack Signing" code-signing certificate and add
# it to the login keychain, once per Mac. build-app.sh signs with it, so every
# build has the same designated requirement and Full Disk Access survives
# updates (an ad-hoc signature changes every build; 31 Oct 2026 test).
#
# Run it yourself in Terminal: it writes to your keychain. It stops if the
# certificate already exists, and deletes its temporary files when done.
set -euo pipefail
trap 'echo "Stopped at line $LINENO (exit $?). Nothing after that ran." >&2' ERR

NAME="PrismPack Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# macOS's own LibreSSL: its .p12 files import into the keychain, unlike
# Homebrew OpenSSL 3's defaults.
OPENSSL=/usr/bin/openssl

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" is already in your login keychain. Nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# 1. A new private key and a certificate for code signing, valid 20 years.
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>"$TMP/req.log" || { cat "$TMP/req.log" >&2; exit 1; }

# 2. Bundle them for import, under a one-time password that's thrown away.
# (Not `tr </dev/urandom | head`: under pipefail its SIGPIPE ended the script
# silently, 31 Oct 2026.)
PASS=$("$OPENSSL" rand -hex 16)
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/cert.p12" -passout "pass:$PASS"

# 3. Import into the login keychain; only codesign may use the key.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

# 4. Check it signs: sign a scratch copy of a system tool.
cp /usr/bin/true "$TMP/check"
codesign --force --sign "$NAME" "$TMP/check"
echo "Created \"$NAME\" in your login keychain. Back it up from Keychain Access (File > Export Items) if you like."
