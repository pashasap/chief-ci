#!/usr/bin/env bash
# Makes a throwaway CA and a localhost server certificate signed by it (SAN localhost, 127.0.0.1, ::1,
# EKU serverAuth, 397 days: what iOS demands of TLS server certificates). Usage: make_cert.sh <out dir>
set -euo pipefail
D=$1; mkdir -p "$D"; cd "$D"
# Prefer a real OpenSSL 3 (Homebrew on the macOS runner); macOS /usr/bin/openssl is LibreSSL.
for c in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl; do [ -x "$c" ] && PATH="$(dirname "$c"):$PATH" && break; done
openssl version
cat > ca.cnf <<'EOF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_ca
[dn]
CN = Kit CI throwaway root
[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF
cat > leaf.ext <<'EOF'
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, IP:127.0.0.1, IP:::1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 30 -config ca.cnf -sha256 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=localhost" -sha256 2>/dev/null
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 397 -sha256 -extfile leaf.ext 2>/dev/null
cat server.pem ca.pem > chain.pem
openssl x509 -in server.pem -noout -subject -ext subjectAltName,extendedKeyUsage 2>/dev/null || openssl x509 -in server.pem -noout -text | grep -A1 -E "Alternative|Extended Key"
