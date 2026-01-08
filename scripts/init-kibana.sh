#!/bin/bash

# Kibana Data View Initialization Script
# Creates data views for auth-session, frontend, backend, and default log types

set -e

KIBANA_HOST="http://kibana:5601"
MAX_ATTEMPTS=30
ATTEMPT=0

echo "⏳ Waiting for Kibana to be ready..."

# Wait for Kibana to start
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s -f "$KIBANA_HOST/api/status" > /dev/null 2>&1; then
        echo "✅ Kibana is ready"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "⏳ Attempt $ATTEMPT/$MAX_ATTEMPTS... waiting"
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "❌ Kibana startup timeout"
    exit 1
fi

echo ""
echo "🔧 Creating Kibana Data Views..."
echo ""

# Function to create a data view
create_data_view() {
    local NAME=$1
    local INDEX_PATTERN=$2
    local TIME_FIELD=$3
    
    echo "📌 Checking data view: $NAME ($INDEX_PATTERN)"
    
    # Check if data view with same config already exists
    EXISTING=$(curl -s -X GET "$KIBANA_HOST/api/saved_objects/_find?type=index-pattern&search_fields=title&search=$INDEX_PATTERN" \
        -H "kbn-xsrf: true" 2>/dev/null)
    
    if echo "$EXISTING" | grep -q "\"title\":\"$INDEX_PATTERN\"" && echo "$EXISTING" | grep -q "\"timeFieldName\":\"$TIME_FIELD\""; then
        echo "  ⏭️  Already exists with same config, skipping"
        return 0
    elif echo "$EXISTING" | grep -q "\"title\":\"$INDEX_PATTERN\""; then
        # Extract ID and update
        EXISTING_ID=$(echo "$EXISTING" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$EXISTING_ID" ]; then
            echo "  🔄 Config differs, updating..."
            RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$KIBANA_HOST/api/saved_objects/index-pattern/$EXISTING_ID" \
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
            if [ "$HTTP_CODE" = "200" ]; then
                echo "  ✅ Updated"
            else
                echo "  ⚠️  Update response (HTTP $HTTP_CODE)"
            fi
            return 0
        fi
    fi
    
    # We use the Saved Objects API to create index-pattern (Data View)
    # This bypasses the UI check for existing indices
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
        echo "  ✅ Created"
    elif [ "$HTTP_CODE" = "409" ]; then
        echo "  ⏭️  Already exists"
    else
        echo "  ⚠️  Response (HTTP $HTTP_CODE)"
        echo "$RESPONSE"
    fi
}

# Create data views for the log types
# These match the data streams: logs-{dataset}-default
# Dataset comes from 'event_domain' extracted in Logstash 
create_data_view "Auth-Session Logs" "logs-auth-session-*" "@timestamp"
# create_data_view "Frontend Logs" "logs-frontend-*" "@timestamp"
# create_data_view "Backend Logs" "logs-backend-*" "@timestamp"
create_data_view "Default Logs" "logs-default-*" "@timestamp"
create_data_view "OHIF Logs" "logs-ohif-*" "@timestamp"
create_data_view "Dictation Backend Logs" "logs-dictation_backend-*" "@timestamp"
create_data_view "Dictation Frontend Logs" "logs-dictation_frontend-*" "@timestamp"
create_data_view "Trace Logs" "logs-trace-*" "@timestamp"
create_data_view "Metrics Logs" "logs-metrics-*" "@timestamp"
# Session Logs merged into Auth-Session Logs
create_data_view "Worklist Logs" "logs-worklist-*" "@timestamp"
create_data_view "Viewer Logs" "logs-viewer-*" "@timestamp"
create_data_view "All Logs" "logs-*" "@timestamp"

echo ""
echo "✅ Kibana Data Views setup completed!"
echo ""
