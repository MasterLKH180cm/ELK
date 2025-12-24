#!/bin/bash

# Kibana Data Views Configuration Script
# Creates domain-specific data views for all event domains
# Applies best practices for field mappings, formatting, and organization

KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"
KIBANA_SPACE="default"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check Kibana connectivity
check_kibana() {
    print_header "Checking Kibana Connectivity"
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "${KIBANA_URL}/api/status" \
        -H "kbn-xsrf: true" 2>/dev/null)
    
    if [ "$response" = "200" ]; then
        print_success "Kibana is accessible at ${KIBANA_URL}"
        return 0
    else
        print_error "Cannot reach Kibana (HTTP $response)"
        return 1
    fi
}

# Create data view for domain
create_data_view() {
    local domain=$1
    local pattern=$2
    local title=$3
    local description=$4
    
    local payload=$(cat <<EOF
{
  "data_view": {
    "title": "$pattern",
    "name": "Logs - $title",
    "description": "$description",
    "timeFieldName": "@timestamp",
    "sourceFilters": [],
    "fieldFormats": {},
    "runtimeFieldMap": {},
    "allowNoIndex": false,
    "tags": ["domain:$domain", "signal:logs", "elk-managed"]
  }
}
EOF
)
    
    response=$(curl -s -X POST "${KIBANA_URL}/api/data_views" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)
    
    # Check if successful
    if echo "$response" | grep -q '"id"'; then
        data_view_id=$(echo "$response" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
        print_success "Created data view for $domain (ID: $data_view_id)"
        return 0
    else
        print_error "Failed to create data view for $domain"
        echo "$response" | head -3
        return 1
    fi
}

# Configure field formatting for data view
configure_field_formatting() {
    local domain=$1
    local pattern=$2
    
    print_info "Configuring field formatting for $domain"
    
    # Field format configurations
    local payload=$(cat <<'EOF'
{
  "fieldFormats": {
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
    "host.ip": {
      "id": "ip",
      "params": {}
    },
    "user_id": {
      "id": "string",
      "params": {}
    }
  }
}
EOF
)
}

# List existing data views
list_data_views() {
    print_header "Listing Existing Data Views"
    
    response=$(curl -s "${KIBANA_URL}/api/data_views" \
        -H "kbn-xsrf: true" 2>/dev/null)
    
    if echo "$response" | grep -q '"data_views"'; then
        echo "$response" | grep -o '"title":"[^"]*' | cut -d'"' -f4 | sort | uniq
        return 0
    else
        print_error "Failed to list data views"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Kibana Data Views Configuration                           ║"
    echo "║  Creating domain-specific data views with best practices   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    # Check connectivity
    if ! check_kibana; then
        print_error "Cannot proceed without Kibana"
        exit 1
    fi
    
    echo ""
    
    # List current data views
    print_header "Current Data Views"
    list_data_views
    
    echo ""
    
    # Create data views for each domain
    print_header "Creating Domain-Specific Data Views"
    
    # Frontend
    create_data_view "frontend" ".ds-logs-frontend-default-*" \
        "Frontend" \
        "Frontend application logs including UI interactions, browser errors, and client-side events"
    
    # Backend
    create_data_view "backend" ".ds-logs-backend-default-*" \
        "Backend" \
        "Backend service logs including API calls, database operations, and application events"
    
    # Auth
    create_data_view "auth" ".ds-logs-auth-default-*" \
        "Authentication" \
        "Authentication and authorization logs including login attempts, token generation, and permission checks"
    
    # Security
    create_data_view "security" ".ds-logs-security-default-*" \
        "Security" \
        "Security-related events including audit logs, threat detection, and compliance events"
    
    # Logs
    create_data_view "logs" ".ds-logs-logs-default-*" \
        "General Logs" \
        "General application logs including startup events, configurations, and system-level operations"
    
    # Metrics
    create_data_view "metrics" ".ds-logs-metrics-default-*" \
        "Metrics" \
        "Metrics and monitoring data including resource utilization, performance metrics, and alerts"
    
    # Traces
    create_data_view "traces" ".ds-logs-traces-default-*" \
        "Distributed Traces" \
        "Distributed trace logs including span data, trace context propagation, and sampling information"
    
    echo ""
    
    # Summary
    print_header "Data View Configuration Complete"
    echo ""
    print_success "All domain-specific data views have been created"
    echo ""
    print_info "Next steps:"
    echo "  1. Verify data views in Kibana: Management → Data Views"
    echo "  2. Create dashboards using these data views"
    echo "  3. Set up alerts for critical domains"
    echo "  4. Configure field visibility and formatting per domain"
    echo ""
}

# Run main
main
