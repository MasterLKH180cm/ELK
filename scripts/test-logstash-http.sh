#!/usr/bin/env bash
set -euo pipefail

payload=${1:-'{"message":"hello from test script","level":"info","source":"test-script"}'}

curl -sSf -X POST "http://localhost:8081" \
  -H "Content-Type: application/json" \
  -d "$payload"

echo -e "\n✓ Payload sent to Logstash HTTP input on port 8081."
