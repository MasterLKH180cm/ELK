#!/bin/bash

# =====================================================================
# Elasticsearch Initialization Script
# =====================================================================
# Purpose: Configure Elasticsearch with ILM policies, component templates,
#          index templates, and data streams from configuration files
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

ES_HOST="${ES_HOST:-http://elasticsearch:9200}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"
CONFIG_DIR="/usr/share/elasticsearch/config"
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

wait_for_elasticsearch() {
    local attempt=0
    
    log_info "Waiting for Elasticsearch to be ready..."
    
    while [ $attempt -lt $MAX_ATTEMPTS ]; do
        if curl -s -f "$ES_HOST/_cluster/health" > /dev/null 2>&1; then
            log_success "Elasticsearch is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        log_info "Attempt $attempt/$MAX_ATTEMPTS... waiting"
        sleep 2
    done
    
    log_error "Elasticsearch startup timeout after $MAX_ATTEMPTS attempts"
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
    
    if [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$ES_HOST$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data" 2>&1)
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$ES_HOST$endpoint" \
            -H "Content-Type: application/json" 2>&1)
    fi
    
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

resource_exists() {
    local endpoint=$1
    
    local response=$(curl -s "$ES_HOST$endpoint" 2>/dev/null)
    
    if echo "$response" | grep -q "error"; then
        return 1
    fi
    
    if [ -n "$response" ] && [ "$response" != "{}" ]; then
        return 0
    fi
    
    return 1
}

# =====================================================================
# ILM Policy Management
# =====================================================================

create_ilm_policy() {
    local policy_name=$1
    local policy_json=$2
    
    log_info "Processing ILM policy: $policy_name"
    
    if resource_exists "/_ilm/policy/$policy_name"; then
        log_info "  Already exists, skipping"
        return 0
    fi
    
    if api_call "PUT" "/_ilm/policy/$policy_name" "$policy_json" "Create ILM policy"; then
        log_success "  Created"
    else
        log_error "  Failed to create"
        return 1
    fi
}

process_ilm_policies() {
    local config_file="$CONFIG_DIR/elasticsearch/ilm-policies.json"
    
    log_step "ILM Policies"
    
    if ! validate_json "$config_file"; then
        return 1
    fi
    
    local policies=$(jq -r '.policies[] | @json' "$config_file")
    
    while IFS= read -r policy; do
        local name=$(echo "$policy" | jq -r '.name')
        local description=$(echo "$policy" | jq -r '.description')
        
        log_debug "Description: $description"
        
        local policy_json=$(echo "$policy" | jq '{policy: {phases: .phases}}')
        
        create_ilm_policy "$name" "$policy_json"
    done <<< "$policies"
}

# =====================================================================
# Component Template Management
# =====================================================================

create_component_template() {
    local template_name=$1
    local template_json=$2
    
    log_info "Processing component template: $template_name"
    
    if resource_exists "/_component_template/$template_name"; then
        log_info "  Already exists, skipping"
        return 0
    fi
    
    if api_call "PUT" "/_component_template/$template_name" "$template_json" "Create component template"; then
        log_success "  Created"
    else
        log_error "  Failed to create"
        return 1
    fi
}

process_component_templates() {
    local config_file="$CONFIG_DIR/elasticsearch/component-templates.json"
    
    log_step "Component Templates"
    
    if ! validate_json "$config_file"; then
        return 1
    fi
    
    local templates=$(jq -r '.component_templates[] | @json' "$config_file")
    
    while IFS= read -r template; do
        local name=$(echo "$template" | jq -r '.name')
        local description=$(echo "$template" | jq -r '.description')
        
        log_debug "Description: $description"
        
        local template_json=$(echo "$template" | jq '{template: .template}')
        
        create_component_template "$name" "$template_json"
    done <<< "$templates"
}

# =====================================================================
# Index Template Management
# =====================================================================

create_index_template() {
    local template_name=$1
    local index_pattern=$2
    local ilm_policy=$3
    local priority=$4
    
    log_info "Processing index template: $template_name ($index_pattern)"
    
    if resource_exists "/_index_template/$template_name"; then
        log_info "  Already exists, skipping"
        return 0
    fi
    
    local template_json=$(cat <<EOF
{
  "index_patterns": ["$index_pattern"],
  "data_stream": {},
  "composed_of": ["logs-mapping", "logs-settings"],
  "priority": $priority,
  "template": {
    "settings": {
      "index.lifecycle.name": "$ilm_policy"
    }
  }
}
EOF
)
    
    if api_call "PUT" "/_index_template/$template_name" "$template_json" "Create index template"; then
        log_success "  Created"
    else
        log_error "  Failed to create"
        return 1
    fi
}

process_index_templates() {
    local config_file="$CONFIG_DIR/elasticsearch/index-templates.json"
    
    log_step "Index Templates"
    
    if ! validate_json "$config_file"; then
        return 1
    fi
    
    local templates=$(jq -r '.index_templates[] | @json' "$config_file")
    
    while IFS= read -r template; do
        local name=$(echo "$template" | jq -r '.name')
        local index_pattern=$(echo "$template" | jq -r '.index_pattern')
        local ilm_policy=$(echo "$template" | jq -r '.ilm_policy')
        local priority=$(echo "$template" | jq -r '.priority')
        local description=$(echo "$template" | jq -r '.description')
        
        log_debug "Description: $description"
        
        create_index_template "$name" "$index_pattern" "$ilm_policy" "$priority"
    done <<< "$templates"
}

# =====================================================================
# Data Stream Management
# =====================================================================

create_data_stream() {
    local stream_name=$1
    
    log_info "Processing data stream: $stream_name"
    
    if resource_exists "/_data_stream/$stream_name"; then
        log_info "  Already exists, skipping"
        return 0
    fi
    
    if api_call "PUT" "/_data_stream/$stream_name" "" "Create data stream"; then
        log_success "  Created"
    else
        log_error "  Failed to create"
        return 1
    fi
}

process_data_streams() {
    local config_file="$CONFIG_DIR/elasticsearch/index-templates.json"
    
    log_step "Data Streams"
    
    if ! validate_json "$config_file"; then
        return 1
    fi
    
    local streams=$(jq -r '.index_templates[].data_stream' "$config_file" | sort -u)
    
    while IFS= read -r stream; do
        if [ -n "$stream" ] && [ "$stream" != "null" ]; then
            create_data_stream "$stream"
        fi
    done <<< "$streams"
}

# =====================================================================
# Validation
# =====================================================================

validate_configuration() {
    log_step "Validating Configuration"
    
    local valid=true
    
    local files=(
        "$CONFIG_DIR/elasticsearch/ilm-policies.json"
        "$CONFIG_DIR/elasticsearch/component-templates.json"
        "$CONFIG_DIR/elasticsearch/index-templates.json"
    )
    
    for file in "${files[@]}"; do
        if ! validate_json "$file"; then
            valid=false
        fi
    done
    
    if [ "$valid" = "false" ]; then
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
    echo "  Elasticsearch Initialization"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "  ES Host: $ES_HOST"
    echo "  Config Dir: $CONFIG_DIR"
    echo "  Dry Run: $DRY_RUN"
    echo "  Verbose: $VERBOSE"
    echo ""
    
    if ! validate_configuration; then
        exit 1
    fi
    
    if ! wait_for_elasticsearch; then
        exit 1
    fi
    
    process_ilm_policies || exit 1
    process_component_templates || exit 1
    process_index_templates || exit 1
    process_data_streams || exit 1
    
    log_step "Initialization Complete"
    log_success "All Elasticsearch resources configured successfully!"
    echo ""
}

main