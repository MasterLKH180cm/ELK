#!/bin/bash

# Kibana Data View Initialization Script
# Creates data views for auth, frontend, backend, and default log types

set -e

KIBANA_HOST="http://kibana:5601"
MAX_ATTEMPTS=30
ATTEMPT=0

echo "??Waiting for Kibana to be ready..."

# Wait for Kibana to start
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s -f "$KIBANA_HOST/api/status" > /dev/null 2>&1; then
        echo "??Kibana is ready"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "??Attempt $ATTEMPT/$MAX_ATTEMPTS... waiting"
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "??Kibana startup timeout"
    exit 1
fi

echo ""
echo "?�� Creating Kibana Data Views..."
echo ""

# Function to create a data view
create_data_view() {
    local NAME=$1
    local INDEX_PATTERN=$2
    local TIME_FIELD=$3
    
    echo "?? Creating data view: $NAME ($INDEX_PATTERN)"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$KIBANA_HOST/api/saved_objects/index-pattern" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{
    \"attributes\": {
        \"name\": \"$NAME\",
        \"title\": \"$INDEX_PATTERN\",
        \"timeFieldName\": \"$TIME_FIELD\"
    }
}")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        echo "  ??Created"
    else
        echo "  ?��?  Response (HTTP $HTTP_CODE)"
    fi
}

# Create data views for the four log types
create_data_view "Auth Logs" "logs-auth-*" "@timestamp"
create_data_view "Frontend Logs" "logs-frontend-*" "@timestamp"
create_data_view "Backend Logs" "logs-backend-*" "@timestamp"
create_data_view "Default Logs" "logs-default-*" "@timestamp"
create_data_view "OHIF Logs" "logs-ohif-*" "@timestamp"
create_data_view "Dictation Backend Logs" "logs-dictation-backend-*" "@timestamp"
create_data_view "Dictation Frontend Logs" "logs-dictation-frontend-*" "@timestamp"
create_data_view "All Logs" "logs-*" "@timestamp"

echo ""
echo "??Kibana Data Views setup completed!"
echo ""
