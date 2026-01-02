#!/bin/bash

# =====================================================================
# Kibana Initialization Script
# =====================================================================
# Purpose: Configure Kibana data views from configuration files
#
# Features:
# - Configuration-driven approach using JSON config files
# - Idempotent operations (safe to run multiple times)
# - Comprehensive validation and error handling
# - Dry-run mode support (DRY_RUN=true)
# - Verbose logging (VERBOSE=true)
# =====================================================================

set -e

# =====================================================================
# Configuration
# =====================================================================

KIBANA_HOST="${KIBANA_HOST:-http://kibana:5601}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"
CONFIG_DIR="/usr/share/kibana/config"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# =====================================================================
# Logging Functions
# =====================================================================

log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_warning() {
    echo "⚠️  $1"
}

log_error() {
    echo "❌ $1" >&2
}

log_debug() {
    if [ "$VERBOSE" = "true" ]; then
        echo "🔍 DEBUG: $1"
    fi
}

log_step() {
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════"
    echo ""
}

# =====================================================================
# Utility Functions
# =====================================================================

wait_for_kibana() {
    local attempt=0
    
    log_info "Waiting for Kibana to be ready..."
    
    while [ $attempt -lt $MAX_ATTEMPTS ]; do
        if curl -s -f "$KIBANA_HOST/api/status" > /dev/null 2>&1; then
            log_success "Kibana is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        log_info "Attempt $attempt/$MAX_ATTEMPTS... waiting"
        sleep 2
    done
    
    log_error "Kibana startup timeout after $MAX_ATTEMPTS attempts"
    return 1
}

validate_json() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        log_error "Configuration file not found: $file"
        return 1
    fi
    
    if ! jq empty "$file" 2>/dev/null; then
        log_error "Invalid JSON in file: $file"
        return 1
    fi
    
    log_debug "Valid JSON: $file"
    return 0
}

api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    local description=$4
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] $method $endpoint"
        log_debug "Data: $data"
        return 0
    fi
    
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" -X "$method" "$KIBANA_HOST$endpoint" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "$data" 2>&1)
    
    http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)
    
    log_debug "HTTP $http_code: $description"
    
    if [[ "$http_code" =~ ^(200|201)$ ]]; then
        return 0
    elif [ "$http_code" = "409" ]; then
        log_debug "Resource already exists (409)"
        return 0
    else
        log_debug "Response body: $body"
        return 1
    fi
}

data_view_exists() {
    local index_pattern=$1
    
    local response=$(curl -s -X GET "$KIBANA_HOST/api/saved_objects/_find?type=index-pattern&search_fields=title&search=$index_pattern" \
        -H "kbn-xsrf: true" 2>/dev/null)
    
    if echo "$response" | grep -q "\"title\":\"$index_pattern\""; then
        return 0
    fi
    
    return 1
}

# =====================================================================
# Data View Management
# =====================================================================

create_data_view() {
    local name=$1
    local index_pattern=$2
    local time_field=$3
    local description=$4
    
    log_info "Processing data view: $name ($index_pattern)"
    log_debug "Description: $description"
    
    if data_view_exists "$index_pattern"; then
        log_info "  Already exists, skipping"
        return 0
    fi
    
    local data_view_json=$(cat <<EOF
{
  "attributes": {
    "name": "$name",
    "title": "$index_pattern",
    "timeFieldName": "$time_field"
  }
}
EOF
)
    
    if api_call "POST" "/api/saved_objects/index-pattern" "$data_view_json" "Create data view"; then
        log_success "  Created"
    else
        log_error "  Failed to create"
        return 1
    fi
}

process_data_views() {
    local config_file="$CONFIG_DIR/kibana/data-views.json"
    
    log_step "Data Views"
    
    if ! validate_json "$config_file"; then
        return 1
    fi
    
    local data_views=$(jq -r '.data_views[] | @json' "$config_file")
    
    while IFS= read -r data_view; do
        local name=$(echo "$data_view" | jq -r '.name')
        local index_pattern=$(echo "$data_view" | jq -r '.index_pattern')
        local time_field=$(echo "$data_view" | jq -r '.time_field')
        local description=$(echo "$data_view" | jq -r '.description')
        
        create_data_view "$name" "$index_pattern" "$time_field" "$description"
    done <<< "$data_views"
}

# =====================================================================
# Validation
# =====================================================================

validate_configuration() {
    log_step "Validating Configuration"
    
    local config_file="$CONFIG_DIR/kibana/data-views.json"
    
    if ! validate_json "$config_file"; then
        log_error "Configuration validation failed"
        return 1
    fi
    
    log_success "Configuration is valid"
    return 0
}

# =====================================================================
# Main Execution
# =====================================================================

main() {
    echo "═══════════════════════════════════════════════════"
    echo "  Kibana Initialization"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "  Kibana Host: $KIBANA_HOST"
    echo "  Config Dir: $CONFIG_DIR"
    echo "  Dry Run: $DRY_RUN"
    echo "  Verbose: $VERBOSE"
    echo ""
    
    if ! validate_configuration; then
        exit 1
    fi
    
    if ! wait_for_kibana; then
        exit 1
    fi
    
    process_data_views || exit 1
    
    log_step "Initialization Complete"
    log_success "All Kibana data views configured successfully!"
    echo ""
}

main
