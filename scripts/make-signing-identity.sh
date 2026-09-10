#!/bin/bash
#
# Creates a self-signed code-signing certificate for local builds.
#
# Why this exists: an ad-hoc signature has no identity, so its designated
# requirement pins the exact bytes of the binary. macOS keys Input Monitoring
# and Accessibility on that requirement, which means every rebuild looks like a
# different application and every rebuild loses its permissions — the app then
# reports "Input Monitoring not granted" until the user grants it again.
#
# A certificate, even a self-signed one, gives a requirement of the form
# `identifier "com.m14ttouch.app" and certificate leaf = H"…"`, which the next
# build satisfies too. Permissions are granted once and stay granted.
#
# This does nothing for other people's Macs: the certificate is trusted only
# here, so a build sent to a friend is still unsigned as far as their Gatekeeper
# is concerned. That is a separate problem with a separate answer (a Developer
# ID), and it is not what this script is for.

set -euo pipefail

NAME="M14t Touch Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "✅ Signing identity \"$NAME\" already exists."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# codeSigning in extendedKeyUsage is what makes the certificate usable by
# codesign; without it the identity is created but never offered.
cat > "$WORK/openssl.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $NAME

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CNF

echo "→ Generating a self-signed certificate…"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -config "$WORK/openssl.cnf" 2>/dev/null

PASSWORD="$(openssl rand -hex 24)"

# The PBE algorithms are named rather than left to OpenSSL. OpenSSL 3 defaults
# to AES-256 with a SHA-256 MAC, which macOS's Security framework refuses to
# read — it reports "MAC verification failed (wrong password?)" for a password
# that is perfectly correct.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASSWORD" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

# -A lets codesign use the key without a prompt on every build. The key never
# leaves the login keychain, and the certificate signs nothing but this app.
echo "→ Importing it into the login keychain…"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -A >/dev/null

# Trust is what makes codesign accept a chain that ends in itself. macOS asks
# for the login password here — that is the one prompt this script needs.
echo "→ Trusting it for code signing (macOS will ask for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "✅ Done. Builds will be signed as \"$NAME\" and keep their permissions."
else
    echo "❌ The certificate was created but is not usable for code signing." >&2
    exit 1
fi
