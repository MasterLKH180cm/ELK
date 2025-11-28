#!/usr/bin/env bash
set -euo pipefail

ES_HOST=${ES_HOST:-localhost}
ES_PORT=${ES_PORT:-9200}
LOGSTASH_HOST=${LOGSTASH_HOST:-localhost}
LOGSTASH_HTTP_PORT=${LOGSTASH_HTTP_PORT:-8081}
LOGSTASH_API_PORT=${LOGSTASH_API_PORT:-9600}
KIBANA_HOST=${KIBANA_HOST:-localhost}
KIBANA_PORT=${KIBANA_PORT:-5601}
TEST_MESSAGE=${TEST_MESSAGE:-"stack verification"}

echo "==> Checking Elasticsearch @ http://$ES_HOST:$ES_PORT"
curl -sSf "http://$ES_HOST:$ES_PORT/_cluster/health?pretty=false" >/dev/null
echo "✓ Elasticsearch healthy."

echo "==> Checking Logstash API @ http://$LOGSTASH_HOST:$LOGSTASH_API_PORT"
curl -sSf "http://$LOGSTASH_HOST:$LOGSTASH_API_PORT/_node/stats" >/dev/null
echo "✓ Logstash node stats reachable."

echo "==> Checking Kibana @ http://$KIBANA_HOST:$KIBANA_PORT"
curl -sSf "http://$KIBANA_HOST:$KIBANA_PORT/api/status" >/dev/null
echo "✓ Kibana status OK."

echo "==> Sending sample event through Logstash HTTP input"
LOGSTASH_HOST=$LOGSTASH_HOST \
LOGSTASH_PORT=$LOGSTASH_HTTP_PORT \
ES_HOST=$ES_HOST \
ES_PORT=$ES_PORT \
scripts/test-logstash-http.sh "$TEST_MESSAGE"

echo "✓ All services verified."
