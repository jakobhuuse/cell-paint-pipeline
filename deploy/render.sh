#!/usr/bin/env bash
# Render head.yaml / compute.yaml into ready-to-paste user-data for the Horizon launch wizard.

# A shared munge.key is generated once and reused on every render so head + compute always match.
set -euo pipefail
cd "$(dirname "$0")"

env_file="${1:-cluster.env}"
if [ ! -f "$env_file" ]; then
  echo "error: $env_file not found. Run:  cp cluster.env.example cluster.env  and edit it." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$env_file"

: "${HEAD_HOST:?set in cluster.env}" "${HEAD_IP:?}" "${TENANT_CIDR:?}" "${COMPUTE_NODES:?}" \
  "${CPUS:?}" "${REAL_MEMORY:?}" "${MEM_SPEC_LIMIT:?}"

if [ ! -f munge.key ]; then
  dd if=/dev/urandom bs=1 count=1024 of=munge.key status=none
  chmod 400 munge.key
  echo "generated munge.key (git-ignored shared cluster secret)"
fi
# Portable across GNU (wraps at 76) and BSD/macOS base64 — strip any newlines.
MUNGE_KEY_B64=$(base64 < munge.key | tr -d '\n')

render() {  # <src> <dst>
  sed -e "s|__MUNGE_KEY_B64__|${MUNGE_KEY_B64}|g" \
      -e "s|__HEAD_HOST__|${HEAD_HOST}|g" \
      -e "s|__HEAD_IP__|${HEAD_IP}|g" \
      -e "s|__TENANT_CIDR__|${TENANT_CIDR}|g" \
      -e "s|__COMPUTE_NODES__|${COMPUTE_NODES}|g" \
      -e "s|__CPUS__|${CPUS}|g" \
      -e "s|__REAL_MEMORY__|${REAL_MEMORY}|g" \
      -e "s|__MEM_SPEC_LIMIT__|${MEM_SPEC_LIMIT}|g" \
      "$1" > "$2"
  echo "wrote $2"
}

render head.yaml    head.local.yaml
render compute.yaml compute.local.yaml

echo
echo "Paste head.local.yaml as the head node's customization script, and compute.local.yaml"
echo "for each compute node, in the Horizon launch wizard."
