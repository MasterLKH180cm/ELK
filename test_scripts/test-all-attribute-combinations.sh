#!/bin/bash

# Comprehensive test script for all log attribute combinations
# Tests: event_domain, event_category, event_type, log_level, environment

BASE_URL="http://localhost:8000/api/logs"
SERVICE_NAME="test-service"
SERVICE_VERSION="1.0.0"

# Valid values from log_attributes_validator.py
ENVIRONMENTS=("dev" "staging" "prod" "test")
LOG_LEVELS=("DEBUG" "INFO" "WARN" "ERROR" "FATAL" "TRACE")
EVENT_DOMAINS=("auth" "frontend" "backend")
EVENT_TYPES=("access" "error" "audit" "validation" "performance" "security")
EVENT_CATEGORIES=("application" "authentication" "database" "api" "security" "infrastructure")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

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
        echo -e "${GREEN}✓ PASS${NC} [${env}|${level}|${domain}|${type}|${category}] HTTP ${http_code}"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗ FAIL${NC} [${env}|${level}|${domain}|${type}|${category}] HTTP ${http_code}"
        echo "Response: ${body}"
    fi
}

# Test Case 1: Basic combinations - one from each category
echo -e "${BLUE}=== Test Case 1: Basic Combinations ===${NC}"
for env in "${ENVIRONMENTS[@]}"; do
    for level in "${LOG_LEVELS[@]}"; do
        test_endpoint "${env}" "${level}" "backend" "access" "api" "Basic test log"
    done
done

# Test Case 2: All Event Domains with fixed other parameters
echo -e "\n${BLUE}=== Test Case 2: All Event Domains ===${NC}"
for domain in "${EVENT_DOMAINS[@]}"; do
    test_endpoint "prod" "INFO" "${domain}" "access" "api" "Event domain test: ${domain}"
done

# Test Case 3: All Event Types with fixed other parameters
echo -e "\n${BLUE}=== Test Case 3: All Event Types ===${NC}"
for type in "${EVENT_TYPES[@]}"; do
    test_endpoint "prod" "INFO" "backend" "${type}" "api" "Event type test: ${type}"
done

# Test Case 4: All Event Categories with fixed other parameters
echo -e "\n${BLUE}=== Test Case 4: All Event Categories ===${NC}"
for category in "${EVENT_CATEGORIES[@]}"; do
    test_endpoint "prod" "INFO" "backend" "access" "${category}" "Event category test: ${category}"
done

# Test Case 5: Cross-domain combinations
echo -e "\n${BLUE}=== Test Case 5: Cross-Domain Combinations ===${NC}"
test_endpoint "dev" "DEBUG" "auth" "validation" "authentication" "Auth validation in dev"
test_endpoint "prod" "ERROR" "security" "audit" "security" "Security audit in production"
test_endpoint "test" "INFO" "database" "performance" "database" "Database performance in test"
test_endpoint "prod" "FATAL" "frontend" "security" "application" "Frontend security issue"
test_endpoint "staging" "TRACE" "cache" "access" "infrastructure" "Cache access in staging"

# Test Case 6: Edge cases with different messages
echo -e "\n${BLUE}=== Test Case 6: Edge Cases ===${NC}"
test_endpoint "prod" "INFO" "backend" "access" "api" "Short"
test_endpoint "prod" "INFO" "backend" "access" "api" "This is a much longer message with multiple words to test message length handling in the system"
test_endpoint "dev" "ERROR" "auth" "error" "authentication" "Authentication failed for user"

# Summary
echo -e "\n${BLUE}==================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}==================================${NC}"
echo -e "Total Tests:  ${TOTAL_TESTS}"
echo -e "${GREEN}Passed:      ${PASSED_TESTS}${NC}"
echo -e "${RED}Failed:      ${FAILED_TESTS}${NC}"
echo -e "${BLUE}==================================${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
