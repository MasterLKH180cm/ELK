#!/bin/bash

# Comprehensive test script for ALL log attribute combinations
# Tests all combinations: environment × log_level × event_domain × event_type × event_category

BASE_URL="http://localhost:8000/api/logs"
SERVICE_NAME="test-service"
SERVICE_VERSION="1.0.0"

# Valid values from log_attributes_validator.py and API implementation
ENVIRONMENTS=("dev" "staging" "prod" "test")
LOG_LEVELS=("DEBUG" "INFO" "WARN" "ERROR" "CRITICAL" "FATAL" "TRACE")
EVENT_DOMAINS=("auth" "session" "dictation_frontend" "dictation_backend" "worklist" "viewer" "ohif" "trace" "metrics" "default")
EVENT_TYPES=("access" "error" "audit" "validation" "performance" "security")
EVENT_CATEGORIES=("frontend" "authentication" "database" "backend" "security" "infrastructure")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
START_TIME=$(date +%s)

# Function to perform curl request and check response
test_endpoint() {
    local env=$1
    local level=$2
    local domain=$3
    local type=$4
    local category=$5
    local message=$6
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Build query parameter
    local query_message=$(echo "${message}" | sed 's/ /%20/g')
    
    # Build curl command
    local response=$(curl -s -w "\n%{http_code}" \
        -X GET "${BASE_URL}?message=${query_message}" \
        -H "X-Service-Name: ${SERVICE_NAME}" \
        -H "X-Service-Version: ${SERVICE_VERSION}" \
        -H "X-Environment: ${env}" \
        -H "X-Log-Level: ${level}" \
        -H "X-Event-Type: ${type}" \
        -H "X-Event-Category: ${category}" \
        -H "X-Event-Domain: ${domain}" \
        -H "Content-Type: application/json")
    
    # Extract HTTP status code (last line)
    local http_code=$(echo "${response}" | tail -n1)
    local body=$(echo "${response}" | head -n-1)
    
    # Check if response is successful (200-299)
    if [[ $http_code =~ ^[2][0-9]{2}$ ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        # Show progress every 10 tests
        if (( TOTAL_TESTS % 10 == 0 )); then
            echo -e "${GREEN}✓${NC} Test ${TOTAL_TESTS}: [${env}|${level}|${domain}|${type}|${category}] HTTP ${http_code}"
        fi
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} Test ${TOTAL_TESTS}: [${env}|${level}|${domain}|${type}|${category}] HTTP ${http_code}"
        echo "  Response: ${body}"
    fi
}

# Display test configuration
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ Comprehensive Log Attribute Combination Test              ║${NC}"
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
echo -e "Starting test run at $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Main test loop: iterate through ALL combinations
test_count=0
for env in "${ENVIRONMENTS[@]}"; do
    for level in "${LOG_LEVELS[@]}"; do
        for domain in "${EVENT_DOMAINS[@]}"; do
            for type in "${EVENT_TYPES[@]}"; do
                for category in "${EVENT_CATEGORIES[@]}"; do
                    test_count=$((test_count + 1))
                    
                    # Create descriptive message
                    message="Test ${test_count}/${TOTAL_COMBINATIONS} - ${domain}/${type}/${category}"
                    
                    # Call test function
                    test_endpoint "${env}" "${level}" "${domain}" "${type}" "${category}" "${message}"
                    
                    # Optional: Add small delay to avoid overwhelming server (every 50 tests)
                    if (( test_count % 50 == 0 )); then
                        echo -e "${YELLOW}Progress: ${test_count}/${TOTAL_COMBINATIONS} tests completed ($(( (test_count * 100) / TOTAL_COMBINATIONS ))%)${NC}"
                        sleep 0.5
                    fi
                done
            done
        done
    done
done

# Calculate execution time
END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME - START_TIME))

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ Test Summary                                               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Total Tests Run:   ${TOTAL_TESTS}"
echo -e "${GREEN}Passed:            ${PASSED_TESTS}${NC}"
echo -e "${RED}Failed:            ${FAILED_TESTS}${NC}"
echo -e "Success Rate:      $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%"
echo -e "Execution Time:    ${EXECUTION_TIME} seconds"
echo -e "Tests per Second:  $(( TOTAL_TESTS / (EXECUTION_TIME + 1) ))"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed!${NC}"
    exit 1
fi
