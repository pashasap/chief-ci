#!/bin/bash
# The stand-in's certificates (issue #94, D-20261126-p-66): a CA made for one run only, and a server certificate for
# localhost signed by it. iOS trusts a server certificate only with an RSA key of 2048 bits or more, a SHA-256
# signature, the host name in subjectAltName, serverAuth in extendedKeyUsage and at most 825 days of validity.
# The keys stay in the folder given as $1 (outside the repository); only ca.crt is handed to the simulator.
set -euo pipefail
D=$1; mkdir -p "$D"
cat > "$D/ca.cnf" <<'CNF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_ca
[dn]
CN = Factory stand-in test CA
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
CNF
cat > "$D/server.cnf" <<'CNF'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = localhost
[v3_server]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost,IP:127.0.0.1,IP:::1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
CNF
openssl req -x509 -newkey rsa:2048 -sha256 -days 30 -nodes -keyout "$D/ca.key" -out "$D/ca.crt" -config "$D/ca.cnf"
openssl req -new -newkey rsa:2048 -sha256 -nodes -keyout "$D/server.key" -out "$D/server.csr" -config "$D/server.cnf"
openssl x509 -req -in "$D/server.csr" -CA "$D/ca.crt" -CAkey "$D/ca.key" -CAcreateserial -out "$D/server.crt" \
  -days 30 -sha256 -extfile "$D/server.cnf" -extensions v3_server
