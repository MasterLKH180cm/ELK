#!/usr/bin/env bash
set -euo pipefail

LOGSTASH_HOST=${LOGSTASH_HOST:-localhost}
LOGSTASH_PORT=${LOGSTASH_PORT:-8081}
ES_HOST=${ES_HOST:-localhost}
ES_PORT=${ES_PORT:-9200}
SLEEP_SECONDS=${SLEEP_SECONDS:-3}

message=${1:-"hello from test script"}
test_id=$(date +%s%N)
payload=$(cat <<JSON
{
  "test_id": "$test_id",
  "source": "test-script",
  "level": "info",
  "message": "$message"
}
JSON
)

curl -sSf -X POST "http://$LOGSTASH_HOST:$LOGSTASH_PORT" \
  -H "Content-Type: application/json" \
  -d "$payload" > /dev/null
echo "✓ Payload sent to Logstash HTTP input ($LOGSTASH_HOST:$LOGSTASH_PORT) with test_id=$test_id."

sleep "$SLEEP_SECONDS"

response=$(curl -sSf "http://$ES_HOST:$ES_PORT/logstash-*/_search?q=test_id:$test_id&size=1")
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN=python
else
  echo "Python is required to validate Elasticsearch hits." >&2
  exit 1
fi

export SEARCH_RESPONSE="$response"
hits=$($PYTHON_BIN - <<'PY'
import json, os
data = json.loads(os.environ["SEARCH_RESPONSE"])
print(data.get("hits", {}).get("total", {}).get("value", 0))
PY
)
unset SEARCH_RESPONSE

if [[ "$hits" -gt 0 ]]; then
  echo "✓ Document confirmed in Elasticsearch (hits=$hits)."
else
  echo "✗ Document not found in Elasticsearch. Check Logstash and Elasticsearch logs." >&2
  exit 1
fi
