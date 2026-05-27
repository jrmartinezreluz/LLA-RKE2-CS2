#!/usr/bin/env bash
# Export internal CA certificate for trusting in Windows / Linux browsers.
set -euo pipefail

OUT="${1:-lla-internal-ca.crt}"
kubectl -n cert-manager get secret lla-internal-ca-secret \
  -o jsonpath='{.data.tls\.crt}' | base64 -d >"$OUT"
echo "Wrote $OUT"
echo "Windows: import into Trusted Root Certification Authorities"
echo "Linux:  sudo cp $OUT /usr/local/share/ca-certificates/lla-internal.crt && sudo update-ca-certificates"
