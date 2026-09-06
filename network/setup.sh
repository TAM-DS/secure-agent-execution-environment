#!/usr/bin/env bash
# setup.sh - reproduce the agent sandbox network topology:
#
#   agent-sandbox-net (internal, no default route out)
#           |
#      agent-proxy (Squid, allowlists egress to api.anthropic.com only)
#           |
#   agent-egress-net (normal bridge, has route out to the internet)
#
# Run from anywhere; squid.conf is resolved relative to this script's location.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQUID_CONF="$SCRIPT_DIR/squid.conf"

# Isolated network for sandboxed agent containers. --internal means Docker
# does not set up a default route to the outside world for containers here.
docker network create --driver bridge --internal agent-sandbox-net

# Normal bridge network with outbound internet access. This is where the
# proxy container reaches the internet from, on behalf of the sandbox.
docker network create --driver bridge agent-egress-net

# Start the proxy on agent-sandbox-net first (docker run only accepts one
# --network at creation time), mounting our allowlist config read-only.
docker run -d --name agent-proxy \
  --network agent-sandbox-net \
  -v "$SQUID_CONF":/etc/squid/squid.conf:ro \
  ubuntu/squid

# Attach the second network so agent-proxy can bridge sandbox -> egress.
docker network connect agent-egress-net agent-proxy

echo "Done. agent-proxy is attached to both agent-sandbox-net and agent-egress-net."
