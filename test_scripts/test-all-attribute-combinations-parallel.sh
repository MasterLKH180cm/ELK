#!/bin/bash

# Parallel execution version for ALL log attribute combinations
# Tests all combinations: environment × log_level × event_domain × event_type × event_category
# Uses GNU parallel or background jobs for concurrent execution

BASE_URL="http://20.14.90.107:8000/api/logs"
SERVICE_NAME="test-service"
SERVICE_VERSION="1.0.0"

# Valid values from log_attributes_validator.py and API implementation
ENVIRONMENTS=("dev" "staging" "prod" "test")
LOG_LEVELS=("DEBUG" "INFO" "WARN" "ERROR" "CRITICAL" "FATAL" "TRACE")
EVENT_DOMAINS=("auth-session" "dictation_frontend" "dictation_backend" "worklist" "viewer" "ohif" "trace" "metrics" "default")
EVENT_TYPES=("access" "error" "audit" "validation" "performance" "security")
EVENT_CATEGORIES=("frontend" "authentication" "database" "backend" "security" "infrastructure")

# Parallel execution settings
MAX_PARALLEL_JOBS=50  # Adjust based on your system and server capacity
PROGRESS_INTERVAL=100  # Update progress every N tests

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Temporary directory for results
RESULTS_DIR=$(mktemp -d)
trap "rm -rf ${RESULTS_DIR}" EXIT

# Test counters (will be calculated from results)
START_TIME=$(date +%s)

# Function to perform curl request and check response
test_endpoint() {
    local env=$1
    local level=$2
    local domain=$3
    local type=$4
    local category=$5
    local message=$6
    local test_num=$7
    
    # Build query parameter
    local query_message=$(echo "${message}" | sed 's/ /%20/g')
    
    # Build curl command
    local response=$(curl -s -w "\n%{http_code}" \
        -X GET "${BASE_URL}?message=${query_message}" \
        -H "X-Service-Name: ${SERVICE_NAME}" \
        -H "X-Service-Version: ${SERVICE_VERSION}" \
        -H "X-Environment: ${env}" \
        -H "X-Log-level: ${level}" \
        -H "X-Event-Type: ${type}" \
        -H "X-Event-Category: ${category}" \
        -H "X-Event-Domain: ${domain}" \
        -H "Content-Type: application/json" 2>&1)
    
    # Extract HTTP status code (last line)
    local http_code=$(echo "${response}" | tail -n1)
    local body=$(echo "${response}" | head -n-1)
    
    # Save result to file
    if [[ $http_code =~ ^[2][0-9]{2}$ ]]; then
        echo "PASS" > "${RESULTS_DIR}/test_${test_num}.result"
    else
        echo "FAIL|${http_code}|${env}|${level}|${domain}|${type}|${category}|${body}" > "${RESULTS_DIR}/test_${test_num}.result"
    fi
}

# Export function and variables for subshells
export -f test_endpoint
export BASE_URL SERVICE_NAME SERVICE_VERSION RESULTS_DIR

# Display test configuration
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ Parallel Log Attribute Combination Test                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Configuration:"
echo -e "  Environments:   ${YELLOW}${#ENVIRONMENTS[@]}${NC} (${ENVIRONMENTS[@]})"
echo -e "  Log Levels:     ${YELLOW}${#LOG_LEVELS[@]}${NC} (${LOG_LEVELS[@]})"
echo -e "  Domains:        ${YELLOW}${#EVENT_DOMAINS[@]}${NC} (${EVENT_DOMAINS[@]})"
echo -e "  Event Types:    ${YELLOW}${#EVENT_TYPES[@]}${NC} (${EVENT_TYPES[@]})"
echo -e "  Categories:     ${YELLOW}${#EVENT_CATEGORIES[@]}${NC} (${EVENT_CATEGORIES[@]})"
echo ""

# Calculate total combinations
TOTAL_COMBINATIONS=$((${#ENVIRONMENTS[@]} * ${#LOG_LEVELS[@]} * ${#EVENT_DOMAINS[@]} * ${#EVENT_TYPES[@]} * ${#EVENT_CATEGORIES[@]}))
echo -e "${CYAN}Total combinations to test: ${TOTAL_COMBINATIONS}${NC}"
echo -e "${CYAN}Max parallel jobs: ${MAX_PARALLEL_JOBS}${NC}"
echo -e "Starting parallel test run at $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check if GNU parallel is available
if command -v parallel &> /dev/null; then
    USE_GNU_PARALLEL=true
    echo -e "${GREEN}Using GNU parallel for optimal performance${NC}"
else
    USE_GNU_PARALLEL=false
    echo -e "${YELLOW}GNU parallel not found, using bash background jobs${NC}"
    echo -e "${YELLOW}Install GNU parallel for better performance: apt-get install parallel${NC}"
fi
echo ""

# Generate all test combinations
test_count=0
if [ "$USE_GNU_PARALLEL" = true ]; then
    # Use GNU parallel for better job control
    for env in "${ENVIRONMENTS[@]}"; do
        for level in "${LOG_LEVELS[@]}"; do
            for domain in "${EVENT_DOMAINS[@]}"; do
                for type in "${EVENT_TYPES[@]}"; do
                    for category in "${EVENT_CATEGORIES[@]}"; do
                        test_count=$((test_count + 1))
                        message="Test ${test_count}/${TOTAL_COMBINATIONS} - ${domain}/${type}/${category}"
                        echo "${env}|${level}|${domain}|${type}|${category}|${message}|${test_count}"
                    done
                done
            done
        done
    done | parallel -j ${MAX_PARALLEL_JOBS} --colsep '\\|' \
        test_endpoint {1} {2} {3} {4} {5} {6} {7}
else
    # Use bash background jobs with manual job control
    set +m  # Disable job control messages to avoid "Done" output clutter
    for env in "${ENVIRONMENTS[@]}"; do
        for level in "${LOG_LEVELS[@]}"; do
            for domain in "${EVENT_DOMAINS[@]}"; do
                for type in "${EVENT_TYPES[@]}"; do
                    for category in "${EVENT_CATEGORIES[@]}"; do
                        test_count=$((test_count + 1))
                        message="Test ${test_count}/${TOTAL_COMBINATIONS} - ${domain}/${type}/${category}"
                        
                        # Copy variables to local scope before backgrounding
                        _env="$env"
                        _level="$level"
                        _domain="$domain"
                        _type="$type"
                        _category="$category"
                        _message="$message"
                        _test_count="$test_count"
                        
                        # Launch test in background with copied values
                        { test_endpoint "$_env" "$_level" "$_domain" "$_type" "$_category" "$_message" "$_test_count"; } &
                        
                        # Limit concurrent jobs
                        if (( $(jobs -r | wc -l) >= MAX_PARALLEL_JOBS )); then
                            wait -n  # Wait for any job to finish
                        fi
                        
                        # Show progress
                        if (( test_count % PROGRESS_INTERVAL == 0 )); then
                            echo -e "${YELLOW}Launched: ${test_count}/${TOTAL_COMBINATIONS} tests ($(( (test_count * 100) / TOTAL_COMBINATIONS ))%)${NC}"
                        fi
                    done
                done
            done
        done
    done
    
    # Wait for all background jobs to complete
    echo -e "${CYAN}Waiting for remaining tests to complete...${NC}"
    wait
    set -m  # Re-enable job control
fi

echo -e "${GREEN}All tests completed, analyzing results...${NC}"
echo ""

# Calculate execution time
END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME - START_TIME))

# Analyze results
TOTAL_TESTS=$(ls ${RESULTS_DIR}/*.result 2>/dev/null | wc -l)
PASSED_TESTS=$(grep -l "^PASS$" ${RESULTS_DIR}/*.result 2>/dev/null | wc -l)
FAILED_TESTS=$((TOTAL_TESTS - PASSED_TESTS))

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ Test Summary                                               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Total Tests Run:   ${TOTAL_TESTS}"
echo -e "${GREEN}Passed:            ${PASSED_TESTS}${NC}"
echo -e "${RED}Failed:            ${FAILED_TESTS}${NC}"
if [ $TOTAL_TESTS -gt 0 ]; then
    echo -e "Success Rate:      $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%"
fi
echo -e "Execution Time:    ${EXECUTION_TIME} seconds"
if [ $EXECUTION_TIME -gt 0 ]; then
    echo -e "Tests per Second:  $(( TOTAL_TESTS / EXECUTION_TIME ))"
fi
echo ""

# Show failed tests details
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed Tests:${NC}"
    echo ""
    grep -h "^FAIL" ${RESULTS_DIR}/*.result | while IFS='|' read -r status http_code env level domain type category body; do
        echo -e "  ${RED}✗${NC} [${env}|${level}|${domain}|${type}|${category}] HTTP ${http_code}"
        if [ -n "${body}" ]; then
            echo -e "    Response: ${body}"
        fi
    done
    echo ""
fi

# Final result
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ ${FAILED_TESTS} tests failed!${NC}"
    exit 1
fi
