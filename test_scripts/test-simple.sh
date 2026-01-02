#!/bin/bash
DOMAINS=("auth" "session" "worklist" "viewer" "ohif" "dictation_backend" "dictation_frontend" "trace" "metrics" "default")
BASE_URL="http://localhost:8000/api/logs"
SUCCESS=0
FAILURE=0

for domain in "${DOMAINS[@]}"; do
  response=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}?message=Test_${domain}" -H "X-Event-Domain: ${domain}")
  http_code=$(echo "$response" | tail -n 1)
  if [ "$http_code" = "200" ]; then
    SUCCESS=$((SUCCESS + 1))
    echo "✓ $domain"
  else
    FAILURE=$((FAILURE + 1))
    echo "✗ $domain - HTTP $http_code"
  fi
done

echo "========================"
echo "Success: $SUCCESS"
echo "Failure: $FAILURE"
echo "========================"
