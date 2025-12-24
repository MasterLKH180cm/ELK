#!/bin/bash

# Create Kibana Data Views for ELK Stack - Enhanced Version
# Purpose: Automate creation of domain-specific data views following best practices
# Usage: bash scripts/create-kibana-data-views-enhanced.sh
# Requirements: curl, jq (optional for pretty output)

set -e

KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"
KIBANA_SPACE="${KIBANA_SPACE:-default}"
POLLING_INTERVAL=2
MAX_RETRIES=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Kibana Data Views Configuration      ║${NC}"
echo -e "${BLUE}║   ELK Stack Domain-Specific Setup      ║${NC}"
echo -e "${BLUE}║   (Enhanced Best Practices Edition)    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check Kibana connectivity
check_kibana() {
    echo -e "${CYAN}[1/5]${NC} Checking Kibana connectivity..."
    echo "      Kibana URL: ${KIBANA_URL}"
    echo ""
    
    for i in $(seq 1 $MAX_RETRIES); do
        if curl -s "${KIBANA_URL}/api/status" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Kibana is accessible and running${NC}"
            echo ""
            return 0
        fi
        
        if [ $i -eq $MAX_RETRIES ]; then
            echo -e "${RED}✗ Kibana is not accessible at ${KIBANA_URL}${NC}"
            echo "  Check if Kibana is running: docker-compose ps"
            echo ""
            return 1
        fi
        
        echo -n "."
        sleep $POLLING_INTERVAL
    done
}

# Check Elasticsearch connectivity and data streams
check_elasticsearch() {
    echo -e "${CYAN}[2/5]${NC} Checking Elasticsearch connectivity..."
    
    local es_url="http://localhost:9200"
    
    for i in $(seq 1 $MAX_RETRIES); do
        if curl -s "${es_url}/_cluster/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Elasticsearch is accessible${NC}"
            
            # Check for data streams
            echo -e "${CYAN}   Checking data streams...${NC}"
            local streams=$(curl -s "${es_url}/_data_stream?expand_wildcards=open" | grep -o '"name":"[^"]*' | cut -d'"' -f4 | wc -l)
            echo -e "${GREEN}✓ Found ${streams} data streams${NC}"
            echo ""
            return 0
        fi
        
        if [ $i -eq $MAX_RETRIES ]; then
            echo -e "${RED}✗ Elasticsearch is not accessible${NC}"
            return 1
        fi
        
        echo -n "."
        sleep $POLLING_INTERVAL
    done
}

# Create a data view
create_data_view() {
    local pattern=$1
    local name=$2
    local description=$3
    local domain=$4
    
    echo -e "${CYAN}   Creating:${NC} $name"
    
    local response=$(curl -s -X POST "${KIBANA_URL}/api/data_views" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{
            \"data_view\": {
                \"title\": \"${pattern}\",
                \"name\": \"${name}\",
                \"description\": \"${description}\",
                \"timeFieldName\": \"@timestamp\",
                \"tags\": [\"domain:${domain}\", \"signal:logs\"],
                \"sourceFilters\": []
            }
        }" 2>/dev/null)
    
    # Check if creation was successful
    if echo "$response" | grep -q '"id"'; then
        local id=$(echo "$response" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
        echo -e "             ${GREEN}✓ Created (ID: ${id})${NC}"
        
        # Configure field formatting
        configure_field_formatting "$id" "$pattern" "$domain"
        
        return 0
    else
        # Check if data view already exists
        if echo "$response" | grep -q 'already exists'; then
            echo -e "             ${YELLOW}⚠ Already exists${NC}"
            return 0
        else
            echo -e "             ${RED}✗ Failed to create${NC}"
            return 1
        fi
    fi
}

# Configure field formatting
configure_field_formatting() {
    local id=$1
    local pattern=$2
    local domain=$3
    
    # Define field formats based on domain
    local formats='{}'
    
    case "$domain" in
        "frontend")
            formats='{
                "http_status_code": {
                    "id": "number",
                    "params": {}
                },
                "event.duration_ms": {
                    "id": "duration",
                    "params": {
                        "inputFormat": "milliseconds",
                        "outputFormat": "humanized"
                    }
                },
                "@timestamp": {
                    "id": "date_time",
                    "params": {
                        "pattern": "YYYY-MM-DD HH:mm:ss"
                    }
                }
            }'
            ;;
        "backend")
            formats='{
                "http_status_code": {
                    "id": "number"
                },
                "event.duration_ms": {
                    "id": "duration",
                    "params": {
                        "inputFormat": "milliseconds",
                        "outputFormat": "humanized"
                    }
                },
                "@timestamp": {
                    "id": "date_time",
                    "params": {
                        "pattern": "YYYY-MM-DD HH:mm:ss"
                    }
                }
            }'
            ;;
        "auth")
            formats='{
                "authenticated": {
                    "id": "boolean"
                },
                "@timestamp": {
                    "id": "date_time",
                    "params": {
                        "pattern": "YYYY-MM-DD HH:mm:ss"
                    }
                }
            }'
            ;;
        "security")
            formats='{
                "log_classification": {
                    "id": "string"
                },
                "@timestamp": {
                    "id": "date_time",
                    "params": {
                        "pattern": "YYYY-MM-DD HH:mm:ss"
                    }
                }
            }'
            ;;
        *)
            formats='{
                "event.duration_ms": {
                    "id": "duration",
                    "params": {
                        "inputFormat": "milliseconds",
                        "outputFormat": "humanized"
                    }
                },
                "@timestamp": {
                    "id": "date_time",
                    "params": {
                        "pattern": "YYYY-MM-DD HH:mm:ss"
                    }
                }
            }'
            ;;
    esac
    
    # Update field formats silently
    curl -s -X POST "${KIBANA_URL}/api/data_views/${id}/fields" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{
            \"fields\": ${formats}
        }" > /dev/null 2>&1 || true
}

# List all data views with details
list_data_views() {
    echo -e "${CYAN}[5/5]${NC} Verifying created data views..."
    echo ""
    
    local response=$(curl -s "${KIBANA_URL}/api/data_views?per_page=100" 2>/dev/null)
    
    if echo "$response" | grep -q '"dataViews"'; then
        local count=$(echo "$response" | grep -o '"title":"[^"]*' | wc -l)
        
        if [ $count -gt 0 ]; then
            echo -e "${GREEN}✓ Successfully found ${count} data view(s)${NC}"
            echo ""
            echo -e "${CYAN}Domain-Specific Data Views:${NC}"
            
            echo "$response" | grep -o '"title":"[^"]*' | cut -d'"' -f4 | grep -E "\.ds-logs-(frontend|backend|auth|security|logs|metrics|traces)-default" | sort | while read title; do
                echo -e "  ${GREEN}✓${NC} $title"
            done
            echo ""
            return 0
        else
            echo -e "${RED}✗ No data views found${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Failed to retrieve data views${NC}"
        return 1
    fi
}

# Generate test queries
generate_test_queries() {
    echo -e "${CYAN}Sample Kibana Queries (Try in Discover/Canvas):${NC}"
    echo ""
    
    cat <<'EOF'
# Query frontend errors in last hour
event_domain:frontend AND level:ERROR AND @timestamp > now-1h

# Query slow backend requests
event_domain:backend AND event.duration_ms > 1000

# Query authentication failures
event_domain:auth AND authenticated:false

# Query all security events
event_domain:security AND log_classification:security

# Query by service
service_name:"api-gateway" AND level:(ERROR OR WARNING)

# Query by HTTP status code
http_status_code >= 400 AND @timestamp > now-24h

# Query high latency by domain
event.duration_ms > 2000 AND event_domain:(frontend OR backend)

# Combined query: Errors in last 4 hours
(level:ERROR OR level:CRITICAL) AND @timestamp > now-4h AND event_domain:*
EOF
    echo ""
}

# Print next steps
print_next_steps() {
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✓ Setup Complete!                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}Next Steps:${NC}"
    echo ""
    echo "1. ${CYAN}Open Kibana:${NC}"
    echo "   ${YELLOW}→${NC} ${KIBANA_URL}"
    echo ""
    echo "2. ${CYAN}Verify Data Views:${NC}"
    echo "   ${YELLOW}→${NC} Management → Data Views"
    echo "   ${YELLOW}→${NC} Should see 7 domain-specific views"
    echo ""
    echo "3. ${CYAN}Explore Data:${NC}"
    echo "   ${YELLOW}→${NC} Analytics → Discover"
    echo "   ${YELLOW}→${NC} Select a data view and start querying"
    echo ""
    echo "4. ${CYAN}Create Dashboards:${NC}"
    echo "   ${YELLOW}→${NC} Analytics → Dashboards → Create dashboard"
    echo "   ${YELLOW}→${NC} Add visualizations for each domain"
    echo ""
    echo "5. ${CYAN}Set Up Alerts:${NC}"
    echo "   ${YELLOW}→${NC} Management → Alerting → Create alert"
    echo "   ${YELLOW}→${NC} Define thresholds per domain"
    echo ""
    
    generate_test_queries
    
    echo -e "${CYAN}Useful Commands:${NC}"
    echo ""
    echo "  # List all data views:"
    echo "  curl -s '${KIBANA_URL}/api/data_views' | grep -o '\"title\":\"[^\"]*'"
    echo ""
    echo "  # Check ES document count:"
    echo "  curl -s 'http://localhost:9200/.ds-logs-*/_count'"
    echo ""
    echo "  # Check ES data streams:"
    echo "  curl -s 'http://localhost:9200/_data_stream?expand_wildcards=open'"
    echo ""
}

# Main execution
main() {
    if ! check_kibana; then
        exit 1
    fi
    
    if ! check_elasticsearch; then
        echo -e "${YELLOW}Warning: Elasticsearch connectivity check failed${NC}"
        echo "Continuing with data view creation..."
        echo ""
    fi
    
    echo -e "${CYAN}[3/5]${NC} Creating data views for all domains..."
    echo ""
    
    # Domain-specific data views
    create_data_view ".ds-logs-frontend-default-*" "Logs - Frontend" \
        "Frontend application logs including UI interactions, browser errors, and client-side events" "frontend"
    
    create_data_view ".ds-logs-backend-default-*" "Logs - Backend" \
        "Backend application logs including API operations, database interactions, and service events" "backend"
    
    create_data_view ".ds-logs-auth-default-*" "Logs - Authentication" \
        "Authentication and authorization logs including login attempts, token lifecycle, and permission checks" "auth"
    
    create_data_view ".ds-logs-security-default-*" "Logs - Security" \
        "Security-related logs including audit events, threat detection, and policy enforcement" "security"
    
    create_data_view ".ds-logs-logs-default-*" "Logs - General" \
        "General system logs including health checks, status updates, and operational events" "logs"
    
    create_data_view ".ds-logs-metrics-default-*" "Logs - Metrics" \
        "Application metrics and monitoring data including resource utilization and performance metrics" "metrics"
    
    create_data_view ".ds-logs-traces-default-*" "Logs - Distributed Traces" \
        "Distributed tracing data including span information, request flows, and trace hierarchy" "traces"
    
    echo ""
    
    # Wait a moment for data to be indexed
    echo -e "${CYAN}[4/5]${NC} Waiting for data synchronization..."
    sleep 3
    echo ""
    
    # List and verify
    list_data_views
    
    # Print completion message
    print_next_steps
}

main
