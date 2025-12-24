#!/bin/bash

# Individual curl command examples for testing log attributes
# Each command tests specific attribute combinations

BASE_URL="http://localhost:8000/api/logs"

echo "=== Environment: DEV ==="
curl -X GET "${BASE_URL}?message=dev%20environment%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: dev" \
  -H "X-Log-Level: DEBUG" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Environment: STAGING ==="
curl -X GET "${BASE_URL}?message=staging%20environment%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: staging" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: validation" \
  -H "X-Event-Category: authentication" \
  -H "X-Event-Domain: auth" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Environment: PROD ==="
curl -X GET "${BASE_URL}?message=production%20environment%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: WARN" \
  -H "X-Event-Type: error" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Environment: TEST ==="
curl -X GET "${BASE_URL}?message=test%20environment%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: test" \
  -H "X-Log-Level: TRACE" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: database" \
  -H "X-Event-Domain: database" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Log Level: DEBUG ==="
curl -X GET "${BASE_URL}?message=debug%20level%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: dev" \
  -H "X-Log-Level: DEBUG" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Log Level: INFO ==="
curl -X GET "${BASE_URL}?message=info%20level%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: dev" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Log Level: WARN ==="
curl -X GET "${BASE_URL}?message=warn%20level%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: dev" \
  -H "X-Log-Level: WARN" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Log Level: ERROR ==="
curl -X GET "${BASE_URL}?message=error%20level%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: ERROR" \
  -H "X-Event-Type: error" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Log Level: FATAL ==="
curl -X GET "${BASE_URL}?message=fatal%20level%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: FATAL" \
  -H "X-Event-Type: error" \
  -H "X-Event-Category: security" \
  -H "X-Event-Domain: security" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Domain: AUTH ==="
curl -X GET "${BASE_URL}?message=auth%20domain%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: authentication" \
  -H "X-Event-Domain: auth" \
  -H "Content-Type: application/json" | jq .


echo -e "\n=== Event Domain: FRONTEND ==="
curl -X GET "${BASE_URL}?message=frontend%20domain%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: dev" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: application" \
  -H "X-Event-Domain: frontend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Domain: BACKEND ==="
curl -X GET "${BASE_URL}?message=backend%20domain%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Domain: SECURITY ==="
curl -X GET "${BASE_URL}?message=security%20domain%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: ERROR" \
  -H "X-Event-Type: security" \
  -H "X-Event-Category: security" \
  -H "X-Event-Domain: security" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Domain: DATABASE ==="
curl -X GET "${BASE_URL}?message=database%20domain%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: performance" \
  -H "X-Event-Category: database" \
  -H "X-Event-Domain: database" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Domain: CACHE ==="
curl -X GET "${BASE_URL}?message=cache%20domain%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: DEBUG" \
  -H "X-Event-Type: performance" \
  -H "X-Event-Category: infrastructure" \
  -H "X-Event-Domain: cache" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Domain: INFRA ==="
curl -X GET "${BASE_URL}?message=infra%20domain%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: WARN" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: infrastructure" \
  -H "X-Event-Domain: infra" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Type: ACCESS ==="
curl -X GET "${BASE_URL}?message=access%20type%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Type: ERROR ==="
curl -X GET "${BASE_URL}?message=error%20type%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: ERROR" \
  -H "X-Event-Type: error" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Type: AUDIT ==="
curl -X GET "${BASE_URL}?message=audit%20type%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: audit" \
  -H "X-Event-Category: security" \
  -H "X-Event-Domain: security" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Type: VALIDATION ==="
curl -X GET "${BASE_URL}?message=validation%20type%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: dev" \
  -H "X-Log-Level: WARN" \
  -H "X-Event-Type: validation" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Type: PERFORMANCE ==="
curl -X GET "${BASE_URL}?message=performance%20type%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: performance" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Type: SECURITY ==="
curl -X GET "${BASE_URL}?message=security%20type%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: ERROR" \
  -H "X-Event-Type: security" \
  -H "X-Event-Category: security" \
  -H "X-Event-Domain: security" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Category: APPLICATION ==="
curl -X GET "${BASE_URL}?message=application%20category%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: dev" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: application" \
  -H "X-Event-Domain: frontend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Category: AUTHENTICATION ==="
curl -X GET "${BASE_URL}?message=authentication%20category%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: validation" \
  -H "X-Event-Category: authentication" \
  -H "X-Event-Domain: auth" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Category: DATABASE ==="
curl -X GET "${BASE_URL}?message=database%20category%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: DEBUG" \
  -H "X-Event-Type: performance" \
  -H "X-Event-Category: database" \
  -H "X-Event-Domain: database" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Category: API ==="
curl -X GET "${BASE_URL}?message=api%20category%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: api" \
  -H "X-Event-Domain: backend" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Category: SECURITY ==="
curl -X GET "${BASE_URL}?message=security%20category%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: ERROR" \
  -H "X-Event-Type: security" \
  -H "X-Event-Category: security" \
  -H "X-Event-Domain: security" \
  -H "Content-Type: application/json" | jq .

echo -e "\n=== Event Category: INFRASTRUCTURE ==="
curl -X GET "${BASE_URL}?message=infrastructure%20category%20test" \
  -H "X-Service-Name: my-service" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: WARN" \
  -H "X-Event-Type: access" \
  -H "X-Event-Category: infrastructure" \
  -H "X-Event-Domain: infra" \
  -H "Content-Type: application/json" | jq .
