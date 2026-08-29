#!/bin/sh
# mTLS bootstrap (atm 1.4.6+ hard requirement, AR 2026-08-29).
# 1.4.6 refuses to start the daemon with "mTLS requires one enabled peer
# interface" / "mTLS requires a configured local identity" until a peer
# interface is registered AND a local TLS identity is configured. The recipe
# mirrors atm-core scripts/smoke/benchmark_mtls.py: self-signed disposable
# cert bundle + `atm peer certificate init`. Idempotent; re-runnable after
# daemon restarts (interface + identity persist in /root/.atm).
# Requires openssl (present in the testbed image).
set -eu

IDIR=/root/.atm/peer
BUNDLE="$IDIR/identity-bundle.pem"

# 1. HTTPS peer interface (bind/advertise local-only; peer mode is OFF by
#    default — this satisfies the mTLS startup gate, nothing is published).
if ! atm peer interface list 2>/dev/null | grep -q "127.0.0.1:43101"; then
  atm peer interface set --bind 127.0.0.1:43101 --advertise-host localhost --enabled
fi

# 2. Local TLS identity — generate only if not already configured.
# (`certificate show` prints "null" with exit 0 when absent — check the value.)
if [ "$(atm peer certificate show 2>/dev/null | head -1)" != "null" ]; then
  echo "mTLS identity already configured"
  exit 0
fi

mkdir -p "$IDIR"
CERT="$IDIR/certificate.pem"; KEY="$IDIR/private-key.pem"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
  -subj "/CN=hermes-testbed.local" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth,clientAuth" \
  -addext "subjectAltName=DNS:hermes-testbed.local,DNS:localhost" \
  -keyout "$KEY" -out "$CERT" 2>/dev/null
chmod 600 "$KEY"
cat "$CERT" "$KEY" > "$BUNDLE"; chmod 600 "$BUNDLE"
FP=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 | sed 's/.*=//' | tr -d ':')
atm peer certificate init --fingerprint "$FP" --private-key-ref "$BUNDLE" --yes
echo "mTLS identity configured (fingerprint $(echo "$FP" | cut -c1-16)...)"
