# FastAPI OpenTelemetry Logging API Documentation

## Overview

FastAPI application with integrated OpenTelemetry (OTel) for comprehensive observability:

- **Tracing**: Distributed tracing with automatic correlation IDs (UUID per request)
- **Logging**: Structured logging with resource attributes and custom fields
- **Metrics**: OpenTelemetry metrics export via OTLP
- **Middleware**: Automatic HTTP request/response logging with exception handling
- **Error Tracking**: Full exception context and stack traces in logs

**Base URL:** `http://localhost:8000`

## Architecture Overview

### Request Processing Flow

```
HTTP Request (GET/POST/etc)
    │
    ├─ Middleware: log_requests
    │  ├─ Generate correlation_id (UUID)
    │  ├─ Create span: {METHOD} {PATH}
    │  ├─ Set span attributes:
    │  │  ├─ http.method
    │  │  ├─ http.url
    │  │  ├─ http.client_ip
    │  │  └─ correlation_id
    │  │
    │  ├─ Call endpoint handler
    │  │
    │  ├─ Set span: http.status_code
    │  ├─ Log: INFO with metadata
    │  └─ On exception: record_exception() + ERROR log
    │
    └─ Endpoint Handler
       ├─ Create local span (endpoint-specific)
       ├─ Set custom attributes
       ├─ Log: INFO/DEBUG with structured fields
       └─ Return response + correlation_id
            │
            ├─ Logger: Send to OTLP Handler
            │  └─ Log Record → OTLP Collector (gRPC)
            │     └─ → Kafka Topic (otel-logs)
            │
            ├─ Tracer: Send to OTLP Handler
            │  └─ Span → OTLP Collector (gRPC)
            │     └─ → Kafka Topic (otel-traces)
            │
            └─ HTTP Response
               └─ Client receives response + headers
```

### Telemetry Pipeline

```
FastAPI Application
    ↓ (Python stdlib logging + OTLP attributes)
OpenTelemetry LoggingHandler
    ↓ (OTLP/gRPC on localhost:4317)
OTLP Collector
    ├─ Receivers: otlp (gRPC on 4317, HTTP on 4318)
    │
    ├─ Processors:
    │  ├─ memory_limiter (512 MiB)
    │  ├─ resourcedetection (env, system)
    │  ├─ transform (extract event.domain from attributes)
    │  └─ batch (256 items, 2s timeout)
    │
    ├─ Domain-Based Filtering (per pipeline):
    │  ├─ filter/auth: event.domain == "auth" → kafka/logs-auth
    │  ├─ filter/session: event.domain == "session" → kafka/logs-session
    │  ├─ filter/worklist: event.domain == "worklist" → kafka/logs-worklist
    │  ├─ filter/viewer: event.domain == "viewer" → kafka/logs-viewer
    │  ├─ filter/dictation_*: event.domain == "dictation_*" → kafka/logs-dictation_*
    │  └─ filter/default: all others → kafka/logs-default
    │
    ├─ Exporters (domain-specific topics):
    │  ├─ kafka/logs-auth → otel-logs-auth
    │  ├─ kafka/logs-session → otel-logs-session
    │  ├─ kafka/logs-worklist → otel-logs-worklist
    │  ├─ kafka/logs-viewer → otel-logs-viewer
    │  ├─ kafka/logs-dictation_backend → otel-logs-dictation_backend
    │  ├─ kafka/logs-dictation_frontend → otel-logs-dictation_frontend
    │  ├─ kafka/logs-default → otel-logs-default
    │  ├─ kafka/traces → otel-traces
    │  ├─ kafka/metrics → otel-metrics
    │  └─ debug (STDOUT logging)
    │
    └─ Extensions: health_check (localhost:13133)

    ↓
Kafka Broker (localhost:29092)
    ├─ Topic: otel-logs-auth (for auth domain logs)
    ├─ Topic: otel-logs-session (for session domain logs)
    ├─ Topic: otel-logs-worklist (for worklist domain logs)
    ├─ Topic: otel-logs-viewer (for viewer domain logs)
    ├─ Topic: otel-logs-dictation_backend
    ├─ Topic: otel-logs-dictation_frontend
    ├─ Topic: otel-logs-default (fallback)
    ├─ Topic: otel-traces (partitions: 1)
    └─ Topic: otel-metrics (partitions: 1)

    ↓
Logstash Consumer
    ├─ Input: Kafka (otel-logs-*, group: logstash-universal-consumer)
    ├─ Filter: Parse OTLP JSON, extract attributes, route by event.domain
    └─ Output: Elasticsearch Data Streams (logs-{domain}-default)

    ↓
Elasticsearch (localhost:9200)
    ├─ Data Stream: logs-auth-default
    ├─ Data Stream: logs-session-default
    ├─ Data Stream: logs-worklist-default
    ├─ Data Stream: logs-viewer-default
    ├─ Data Stream: logs-dictation_backend-default
    ├─ Data Stream: logs-dictation_frontend-default
    ├─ Data Stream: logs-default-default (fallback)
    └─ Each backed by index: .ds-logs-{domain}-default-YYYY.MM.DD-000001

    ↓
Kibana (localhost:5601)
    ├─ Data View: "Auth Logs" (logs-auth-*)
    ├─ Data View: "Session Logs" (logs-session-*)
    ├─ Data View: "Worklist Logs" (logs-worklist-*)
    ├─ Data View: "Viewer Logs" (logs-viewer-*)
    ├─ Data View: "All Logs" (logs-*)
    └─ Discover, Visualizations, Dashboards
```

## API Endpoints

### 1. Health Check

**Endpoint:** `GET /healthz`

Health check to verify the service is running and collecting telemetry.

#### Request

```bash
curl http://localhost:8000/healthz
```

#### Response

```json
{
  "status": "ok"
}
```

**HTTP Status:** 200 OK

#### Telemetry Details

| Attribute | Value |
|-----------|-------|
| Span Name | `healthz` |
| Log Level | INFO |
| Log Message | `Health check` |

#### Example Log in Elasticsearch

```json
{
  "@timestamp": "2024-01-15T10:30:45.123Z",
  "service.name": "fastapi-otel",
  "service.version": "1.0.0",
  "service.instance.id": "instance-1",
  "deployment.environment": "development",
  "host.name": "docker-host",
  "log.level": "INFO",
  "message": "Health check",
  "endpoint": "/healthz",
  "status": "ok"
}
```

---

### 2. Get Logs (Log Message Submission)

**Endpoint:** `GET /api/logs`

Submit a log message with comprehensive OpenTelemetry instrumentation, automatic tracing, correlation tracking, and optional metadata enrichment. Supports structured logging with custom attributes, validation, and PII protection.

#### Overview

- **Method**: GET
- **Path**: `/api/logs`
- **Base URL**: `http://localhost:8000`
- **Response Code**: 200 OK
- **Content Type**: application/json

#### Query Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `message` | string | No | `"sample log"` | The log message content to record |

#### Request Headers (All Optional, Recommended for Full Enrichment)

| Header | Type | Valid Values | Default | Description |
|--------|------|--------------|---------|-------------|
| `X-Service-Name` | string | Any | `"unknown-service"` | Name of the service generating the log |
| `X-Service-Version` | string | Semantic version | `1.0.0` (from env) | Version of the service |
| `X-Environment` | string | `dev`, `staging`, `prod`, `test` | `dev` (from env) | Deployment environment |
| `X-Log-Level` | string | `DEBUG`, `INFO`, `WARN`, `ERROR`, `CRITICAL`, `FATAL`, `TRACE` | `INFO` | Severity level of the log |
| `X-Event-Type` | string | `access`, `error`, `audit`, `validation`, `performance`, `security` | `access` | Type of event being logged |
| `X-Event-Category` | string | `frontend`, `authentication`, `database`, `backend`, `security`, `infrastructure` | `backend` | Technical category of the event |
| `X-Event-Domain` | string | `auth`, `session`, `dictation_frontend`, `dictation_backend`, `worklist`, `viewer`, `ohif`, `trace`, `metrics`, `default` | `default` | Business or technical domain (determines Kafka topic & data stream routing) |
| `Content-Type` | string | `application/json` | Optional | HTTP content type hint |

#### Request Examples

##### Basic Request (cURL)
```bash
curl http://localhost:8000/api/logs
```

##### Custom Message
```bash
curl "http://localhost:8000/api/logs?message=User%20authentication%20successful"
```

##### Domain-Specific Examples (PowerShell)

```powershell
# Auth Domain - Authentication and authorization logs
curl.exe -X GET "http://localhost:8000/api/logs?message=User%20login%20successful" `
  -H "X-Service-Name: auth-api" `
  -H "X-Service-Version: 1.2.0" `
  -H "X-Environment: prod" `
  -H "X-Log-Level: INFO" `
  -H "X-Event-Type: audit" `
  -H "X-Event-Category: authentication" `
  -H "X-Event-Domain: auth"
# → Routes to: otel-logs-auth → logs-auth-default

# Session Domain - User session management
curl.exe -X GET "http://localhost:8000/api/logs?message=Session%20created" `
  -H "X-Service-Name: session-service" `
  -H "X-Service-Version: 2.0.0" `
  -H "X-Environment: prod" `
  -H "X-Log-Level: INFO" `
  -H "X-Event-Type: access" `
  -H "X-Event-Category: backend" `
  -H "X-Event-Domain: session"
# → Routes to: otel-logs-session → logs-session-default

# Worklist Domain - Task and worklist operations
curl.exe -X GET "http://localhost:8000/api/logs?message=Worklist%20query%20executed" `
  -H "X-Service-Name: worklist-api" `
  -H "X-Service-Version: 1.5.0" `
  -H "X-Environment: prod" `
  -H "X-Log-Level: INFO" `
  -H "X-Event-Type: access" `
  -H "X-Event-Category: database" `
  -H "X-Event-Domain: worklist"
# → Routes to: otel-logs-worklist → logs-worklist-default

# Viewer Domain - Medical image viewer logs
curl.exe -X GET "http://localhost:8000/api/logs?message=Image%20loaded" `
  -H "X-Service-Name: viewer-service" `
  -H "X-Service-Version: 3.1.0" `
  -H "X-Environment: prod" `
  -H "X-Log-Level: INFO" `
  -H "X-Event-Type: access" `
  -H "X-Event-Category: frontend" `
  -H "X-Event-Domain: viewer"
# → Routes to: otel-logs-viewer → logs-viewer-default

# Dictation Backend Domain - Server-side dictation processing
curl.exe -X GET "http://localhost:8000/api/logs?message=Audio%20transcription%20completed" `
  -H "X-Service-Name: dictation-backend" `
  -H "X-Service-Version: 1.0.0" `
  -H "X-Environment: prod" `
  -H "X-Log-Level: INFO" `
  -H "X-Event-Type: access" `
  -H "X-Event-Category: backend" `
  -H "X-Event-Domain: dictation_backend"
# → Routes to: otel-logs-dictation_backend → logs-dictation_backend-default

# Dictation Frontend Domain - Client-side dictation UI
curl.exe -X GET "http://localhost:8000/api/logs?message=Recording%20started" `
  -H "X-Service-Name: dictation-frontend" `
  -H "X-Service-Version: 2.3.0" `
  -H "X-Environment: prod" `
  -H "X-Log-Level: INFO" `
  -H "X-Event-Type: access" `
  -H "X-Event-Category: frontend" `
  -H "X-Event-Domain: dictation_frontend"
# → Routes to: otel-logs-dictation_frontend → logs-dictation_frontend-default

# OHIF Domain - OHIF viewer logs (from Azure EventHub)
curl.exe -X GET "http://localhost:8000/api/logs?message=DICOM%20series%20loaded" `
  -H "X-Service-Name: ohif-viewer" `
  -H "X-Service-Version: 3.0.0" `
  -H "X-Environment: prod" `
  -H "X-Log-Level: INFO" `
  -H "X-Event-Type: access" `
  -H "X-Event-Category: frontend" `
  -H "X-Event-Domain: ohif"
# → Routes to: otel-logs-ohif → logs-ohif-default

# Default Domain - Fallback for unspecified or general logs
curl.exe -X GET "http://localhost:8000/api/logs?message=General%20application%20log" `
  -H "X-Service-Name: generic-service" `
  -H "X-Service-Version: 1.0.0" `
  -H "X-Environment: dev" `
  -H "X-Log-Level: INFO" `
  -H "X-Event-Type: access" `
  -H "X-Event-Category: backend" `
  -H "X-Event-Domain: default"
# → Routes to: otel-logs-default → logs-default-default
```

##### Verification Commands

```powershell
# After sending logs, verify routing (wait 3-5 seconds for processing):
Start-Sleep -Seconds 4

# Check specific domain in Kafka
docker exec kafka kafka-console-consumer.sh `
  --bootstrap-server localhost:9092 `
  --topic otel-logs-auth `
  --max-messages 1 `
  --from-beginning

# Check specific domain in Elasticsearch
curl.exe -s "http://localhost:9200/logs-auth-default/_search?size=1&sort=@timestamp:desc" | ConvertFrom-Json | Select-Object -ExpandProperty hits | Select-Object -ExpandProperty hits | Select-Object -ExpandProperty _source | Select-Object message, "event.domain", "@timestamp"

# Count logs per domain
curl.exe -s "http://localhost:9200/logs-auth-default/_count" | ConvertFrom-Json | Select-Object count
curl.exe -s "http://localhost:9200/logs-session-default/_count" | ConvertFrom-Json | Select-Object count
curl.exe -s "http://localhost:9200/logs-worklist-default/_count" | ConvertFrom-Json | Select-Object count
curl.exe -s "http://localhost:9200/logs-viewer-default/_count" | ConvertFrom-Json | Select-Object count
```

##### With PowerShell (Alternative Syntax)
```powershell
$headers = @{
    "X-Service-Name" = "auth-api"
    "X-Service-Version" = "1.0.0"
    "X-Environment" = "prod"
    "X-Log-Level" = "INFO"
    "X-Event-Type" = "access"
    "X-Event-Category" = "authentication"
    "X-Event-Domain" = "auth"
}

$response = Invoke-WebRequest `
    -Uri "http://localhost:8000/api/logs?message=Authentication%20successful" `
    -Headers $headers `
    -Method GET

$response.Content | ConvertFrom-Json
```

##### With Python
```python
import requests

headers = {
    "X-Service-Name": "auth-api",
    "X-Service-Version": "1.0.0",
    "X-Environment": "prod",
    "X-Log-Level": "INFO",
    "X-Event-Type": "access",
    "X-Event-Category": "authentication",
    "X-Event-Domain": "auth"
}

response = requests.get(
    "http://localhost:8000/api/logs",
    params={"message": "Authentication successful"},
    headers=headers
)

print(response.json())
```

##### Batch Testing - All Domains

```powershell
# Test all domains sequentially
@("auth", "session", "worklist", "viewer", "dictation_backend", "dictation_frontend", "ohif", "default") | ForEach-Object {
    $domain = $_
    Write-Host "Testing domain: $domain"
    curl.exe -X GET "http://localhost:8000/api/logs?message=Test-$domain-log" `
        -H "X-Service-Name: test-service" `
        -H "X-Event-Domain: $domain"
}

# Wait for processing
Start-Sleep -Seconds 5

# Verify all domains in Elasticsearch
@("auth", "session", "worklist", "viewer", "dictation_backend", "dictation_frontend", "ohif", "default") | ForEach-Object {
    $count = (curl.exe -s "http://localhost:9200/logs-$_-default/_count" | ConvertFrom-Json).count
    Write-Host "logs-$_-default: $count logs"
}
```

##### Utility Scripts (Bash)
```bash
# Extract and print correlation ID
CORR_ID=$(curl -s "http://localhost:8000/api/logs?message=test" | jq -r '.correlation_id')
echo "Correlation ID: $CORR_ID"

# Pretty print response
curl -s "http://localhost:8000/api/logs?message=test" | jq '.'

# Test all domains (Bash)
for domain in auth session worklist viewer dictation_backend dictation_frontend ohif default; do
  echo "Testing domain: $domain"
  curl -s "http://localhost:8000/api/logs?message=Test-$domain-log" \
    -H "X-Service-Name: test-service" \
    -H "X-Event-Domain: $domain"
  sleep 0.2
done

# Verify domain routing
for domain in auth session worklist viewer dictation_backend dictation_frontend ohif default; do
  count=$(curl -s "http://localhost:9200/logs-$domain-default/_count" | jq '.count')
  echo "logs-$domain-default: $count logs"
done
```

#### Response

**HTTP Status:** 200 OK

```json
{
  "logged": "User authentication successful",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `logged` | string | The exact message that was logged (echoes the query parameter) |
| `correlation_id` | UUID | Unique identifier (v4) for request tracing across the entire system |

#### Log Attributes (Generated Automatically)

**Service Metadata** (from environment or headers):
```json
{
  "service.name": "fastapi-otel",
  "service.version": "1.0.0",
  "service.instance.id": "instance-1",
  "deployment.environment": "development",
  "host.name": "docker-host"
}
```

**Request-Specific Attributes:**
```json
{
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "request_message": "User authentication successful",
  "message_length": 31,
  "log.level": "INFO",
  "event.type": "access",
  "event.category": "authentication",
  "event.domain": "auth"
}
```

**Note:** The `event.domain` attribute is **critical for routing**. It determines:
1. Which OTEL Collector pipeline processes the log
2. Which Kafka topic receives the message (`otel-logs-{domain}`)
3. Which Elasticsearch data stream stores the log (`logs-{domain}-default`)
4. Which Kibana data view displays the log

#### Validation & Constraints

**Mandatory Attributes** (automatically enforced):
- `service.name` - Must not be empty
- `deployment.environment` - Must be one of: `dev`, `staging`, `prod`, `test`
- `log.level` - Must be one of: `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`, `TRACE`
- `event.domain` - Determines routing. Valid values: `auth`, `session`, `dictation_frontend`, `dictation_backend`, `worklist`, `viewer`, `ohif`, `trace`, `metrics`, `default`
- `event.type` - Must be one of: `access`, `error`, `audit`, `validation`, `performance`, `security`

**Forbidden Keywords** (automatically redacted for PII protection):
- `password`, `secret`, `token`, `api_key`
- `credit_card`, `ssn`, `national_id`

If detected, PII is automatically masked with `[REDACTED_*]` patterns.

#### Telemetry Details

**OpenTelemetry Span:**
- Span Name: `get_logs`
- Span Attributes:
  - `correlation_id`
  - `request_message`
  - `service.name`
  - `environment`

**Log Export:**
- Exporter: OTLP gRPC
- Endpoint: `otel-collector:4317` (configurable via `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`)
- Protocol: OpenTelemetry Protocol (OTLP)

#### Example Log Entry in Elasticsearch

```json
{
  "@timestamp": "2024-01-15T10:30:45.123Z",
  "message": "Received log request: User authentication successful",
  "log.level": "INFO",
  "service.name": "fastapi-otel",
  "service.version": "1.0.0",
  "service.instance.id": "instance-1",
  "deployment.environment": "production",
  "host.name": "docker-host",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "request_message": "User authentication successful",
  "message_length": 31,
  "event.domain": "auth",
  "event.type": "access",
  "event.category": "authentication"
}
```

#### Error Handling & Fallbacks

If attribute validation fails:
1. A WARNING is logged
2. Missing mandatory attributes are filled with defaults from environment variables
3. The request proceeds normally with HTTP 200
4. Full enrichment is attempted using `LogAttributesEnricher`

**Example: Missing X-Environment Header**
```bash
curl "http://localhost:8000/api/logs?message=test" \
  -H "X-Service-Name: api"
# X-Environment defaults to "dev"
# Response: HTTP 200 with valid correlation_id
```

#### Performance Characteristics

- **Latency**: < 10ms (local processing)
- **Async logging**: Non-blocking, logs batch exported via OTLP
- **Batch size**: 256 log records (configurable)
- **Timeout**: 2 seconds before export (configurable)
- **Throughput**: ~1000 req/sec per instance

---

## Automatic Middleware Logging

All HTTP requests are automatically logged by the `log_requests` middleware with comprehensive metadata.

### Middleware Behavior

1. **Request Entry**
   - Generate unique `correlation_id` (UUID)
   - Create OpenTelemetry span: `{METHOD} {PATH}`
   - Set span attributes: method, URL, client IP, correlation_id

2. **Request Processing**
   - Call endpoint handler
   - Capture response status code

3. **Logging**
   - Log request/response with HTTP metadata
   - Include correlation_id for request tracking
   - Include client IP for debugging

4. **Exception Handling**
   - Record exception in span
   - Log ERROR level with exception details
   - Include stack trace for debugging

### Request Log Example (200 OK)

```json
{
  "@timestamp": "2024-01-15T10:30:45.123Z",
  "service.name": "fastapi-otel",
  "service.version": "1.0.0",
  "service.instance.id": "instance-1",
  "deployment.environment": "development",
  "host.name": "docker-host",
  "log.level": "INFO",
  "message": "GET /api/logs",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "http.method": "GET",
  "http.url": "/api/logs?message=test",
  "http.status_code": 200,
  "http.client_ip": "127.0.0.1"
}
```

### Error Log Example (500 Error)

```json
{
  "@timestamp": "2024-01-15T10:31:00.456Z",
  "service.name": "fastapi-otel",
  "service.version": "1.0.0",
  "log.level": "ERROR",
  "message": "Request failed: GET /api/logs",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "http.method": "GET",
  "http.url": "/api/logs",
  "http.status_code": 500,
  "http.client_ip": "127.0.0.1",
  "error.type": "ValueError",
  "error.message": "Invalid input parameter",
  "error.stack_trace": "Traceback (most recent call last):\n  File ...\n    raise ValueError(...)"
}
```

---

## Testing & Validation Guide

### Prerequisites

```bash
# 1. Start all services
make up

# 2. Verify services are running
make ps

# 3. Install Python dependencies
make sync

# 4. Start FastAPI application (in another terminal)
make dev
```

### Basic Endpoint Tests

#### Health Check

```bash
# Simple health check
curl http://localhost:8000/healthz

# Verbose output
curl -v http://localhost:8000/healthz

# With response headers
curl -i http://localhost:8000/healthz

# Pretty print with jq
curl -s http://localhost:8000/healthz | jq '.'
```

#### Log Endpoint

```bash
# Default message
curl http://localhost:8000/api/logs

# Custom message
curl "http://localhost:8000/api/logs?message=test%20message"

# Extract correlation_id
CORR_ID=$(curl -s "http://localhost:8000/api/logs?message=test" | jq -r '.correlation_id')
echo "Correlation ID: $CORR_ID"

# Pretty print response
curl -s "http://localhost:8000/api/logs?message=hello" | jq '.'
```

### Load Testing

```bash
# Sequential load test (10 requests)
for i in {1..10}; do
  curl -s "http://localhost:8000/api/logs?message=load_test_$i"
done

# Parallel load test (10 concurrent)
seq 1 10 | xargs -P 10 -I {} curl -s "http://localhost:8000/api/logs?message=concurrent_{}"

# Load test with timestamps
for i in {1..5}; do
  echo "[$(date)] Request $i"
  curl -s "http://localhost:8000/api/logs?message=test_$i" | jq '.'
  sleep 0.5
done
```

### Telemetry Infrastructure Tests

#### OTLP Collector

```bash
# Health check
curl http://localhost:13133/

# View collector metrics
curl http://localhost:8888/metrics | head -20

# View collector logs
docker-compose logs -f otel-collector

# Test connectivity from collector to Kafka
docker-compose exec otel-collector nc -zv kafka 29092
```

#### Kafka

```bash
# Test Kafka connectivity (Makefile)
make test-kafka

# List Kafka topics
docker exec kafka kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list

# View auth logs (last 5)
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs-auth \
  --max-messages 5

# Monitor real-time auth logs
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs-auth \
  --from-beginning

# View all log topics
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic 'otel-logs-.*' \
  --from-beginning

# Check consumer group lag
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group logstash-otel-consumer \
  --describe

# Access Kafka UI
# Open: http://localhost:8888
```

#### Logstash

```bash
# Check Logstash health
curl http://localhost:9600/_node/stats | jq '.pipelines'

# View Logstash logs (errors)
docker-compose logs logstash | grep -i error | tail -20

# Verify Logstash-Kafka connectivity
docker-compose exec logstash nc -zv kafka 29092
```

#### Elasticsearch

```bash
# Cluster health
curl http://localhost:9200/_cluster/health | jq '.'

# List indices
curl http://localhost:9200/_cat/indices?v

# Count all logs
curl http://localhost:9200/logs-*/_count | jq '.count'

# Count auth logs specifically
curl http://localhost:9200/logs-auth-default/_count | jq '.count'

# Count logs from last hour
curl -X POST http://localhost:9200/logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "range": { "@timestamp": { "gte": "now-1h" } } }
  }' | jq '.hits.total.value'
```

#### Kibana

```bash
# Health check
curl http://localhost:5601/api/status | jq '.version'

# Access Kibana UI
# Open: http://localhost:5601
```

### Data Search Tests

#### By Correlation ID

```bash
# Generate a test log
CORR_ID=$(curl -s "http://localhost:8000/api/logs?message=test" | jq -r '.correlation_id')

# Search by correlation_id (all logs)
curl -X POST http://localhost:9200/logs-*/_search \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": { \"match\": { \"correlation_id\": \"$CORR_ID\" } },
    \"size\": 10
  }" | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message, domain: ._source["event.domain"]}'
```

#### By Service

```bash
# Search by service name
curl -X POST http://localhost:9200/logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match": { "service.name": "fastapi-otel" } },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 10
  }' | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message, level: ._source["log.level"], domain: ._source["event.domain"]}'
```

#### By Log Level

```bash
# Search ERROR logs
curl -X POST http://localhost:9200/logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match": { "log.level": "ERROR" } },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 20
  }' | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message, domain: ._source["event.domain"]}'

# Search auth-specific ERROR logs
curl -X POST http://localhost:9200/logs-auth-default/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match": { "log.level": "ERROR" } },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 20
  }' | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message}'
```

#### Recent Logs

```bash
# Get last 20 logs (last hour, all domains)
curl -X POST http://localhost:9200/logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "range": { "@timestamp": { "gte": "now-1h" } } },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 20
  }' | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message, level: ._source["log.level"], domain: ._source["event.domain"]}'
```

### Kibana Setup

1. **Access Kibana**
   - Open: http://localhost:5601

2. **Create Data Views**
   - Navigate: **Stack Management** → **Data Views**
   - Click: **Create data view**
   - Create multiple data views for different domains:
     - Name: `Auth Logs`, Pattern: `logs-auth-*`, Time field: `@timestamp`
     - Name: `Session Logs`, Pattern: `logs-session-*`, Time field: `@timestamp`
     - Name: `All Logs`, Pattern: `logs-*`, Time field: `@timestamp`
   - Click: **Save data view to Kibana**

3. **Browse Logs**
   - Navigate: **Discover**
   - Select: `Auth Logs` or `All Logs` data view
   - View log entries filtered by domain
   - Use KQL queries: `event.domain: "auth"` or `service.name: "auth-api"`

4. **Create Visualization**
   - Navigate: **Visualize Library** → **Create new visualization**
   - Type: Bar chart
   - Data view: `otel-logs-*`
   - X-axis: `log.level`
   - Title: "Logs by Level"
   - Save

### Full Stack Integration Test

```bash
# Run automated test (Makefile)
make test-stack

# Manual end-to-end test
echo "=== Step 1: Generate test logs..."
for i in {1..3}; do
  curl -s "http://localhost:8000/api/logs?message=e2e_test_$i"
done

echo "=== Step 2: Check OTLP Collector..."
curl -s http://localhost:13133/

echo "=== Step 3: Check Kafka..."
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
  --max-messages 1

echo "=== Step 4: Check Elasticsearch..."
curl -s http://localhost:9200/logs-*/_count | jq '.count'

echo "=== Step 5: View in Kibana..."
echo "Open: http://localhost:5601"
```

---

## Log Schema (ECS Compliance)

### Standard Fields

```json
{
  "@timestamp": "2024-01-15T10:30:45.123Z",
  "message": "Log message text",
  "log.level": "INFO",
  
  "service.name": "fastapi-otel",
  "service.version": "1.0.0",
  "service.instance.id": "instance-1",
  
  "deployment.environment": "development",
  
  "host.name": "docker-host",
  "host.hostname": "docker-host",
  
  "http.method": "GET",
  "http.url": "/api/logs?message=test",
  "http.status_code": 200,
  "http.client_ip": "127.0.0.1",
  
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

### Endpoint-Specific Fields

#### `/healthz`
```json
{
  "endpoint": "/healthz",
  "status": "ok"
}
```

#### `/api/logs`
```json
{
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "request_message": "hello world",
  "message_length": 11
}
```

---

## Performance Characteristics

### Batching & Timeouts

| Component | Setting | Value |
|-----------|---------|-------|
| OTLP Exporter | Batch Size | 256 records |
| OTLP Exporter | Timeout | 2 seconds |
| OTLP Exporter | Max Queue Size | 2048 |
| Memory Limiter | Limit | 512 MiB |

### Sampling & Retention

| Component | Setting | Value |
|-----------|---------|-------|
| Trace Sampling | Rate | 100% (all traces) |
| Log Retention (ES) | Days | Configurable (default: 30) |
| Index Rollover | Frequency | Daily (YYYY.MM.dd) |

### Throughput

- **FastAPI**: ~1000 req/sec (single instance)
- **Kafka**: ~10k msg/sec per broker
- **Elasticsearch**: ~5k docs/sec per node (single)
- **Logstash**: ~2k msg/sec per pipeline

---

## Common Issues & Solutions

### No Logs in Elasticsearch

**Symptom:** Elasticsearch indices are empty after API requests.

**Debug Steps:**

1. **Verify FastAPI is receiving requests:**
   ```bash
   curl http://localhost:8000/api/logs?message=test
   docker-compose logs fastapi_app | grep -i "log request"
   ```

2. **Check OTLP Collector:**
   ```bash
   curl http://localhost:13133/
   docker-compose logs otel-collector | grep -i "received\|exported"
   ```

3. **Check Kafka messages:**
   ```bash
   # Check auth domain logs
   docker exec kafka kafka-console-consumer.sh \
     --bootstrap-server localhost:9092 \
     --topic otel-logs-auth \
     --max-messages 3 \
     --from-beginning
   
   # Or check default/fallback logs
   docker exec kafka kafka-console-consumer.sh \
     --bootstrap-server localhost:9092 \
     --topic otel-logs-default \
     --max-messages 3 \
     --from-beginning
   ```

4. **Check Logstash errors:**
   ```bash
   docker-compose logs logstash | grep -i error
   ```

5. **Check Elasticsearch data streams:**
   ```bash
   # List all data streams
   curl http://localhost:9200/_data_stream | jq '.data_streams[].name'
   
   # Or check indices
   curl http://localhost:9200/_cat/indices?v | grep logs-
   ```

**Resolution:** Follow each debug step and check logs. Most issues are network connectivity or configuration mismatches.

### Correlation ID Tracking

**Verify correlation_id flow through pipeline:**

```bash
# 1. Get a correlation_id from API
CORR_ID=$(curl -s "http://localhost:8000/api/logs?message=trace_test" | jq -r '.correlation_id')
echo "Correlation ID: $CORR_ID"

# 2. Check FastAPI logs
docker-compose logs fastapi_app | grep "$CORR_ID"

# 3. Check OTLP Collector logs
docker-compose logs otel-collector | grep "$CORR_ID"

# 4. Check Kafka message (try auth topic first, then default)
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs-auth \
  --max-messages 10 | grep "$CORR_ID" || \
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs-default \
  --max-messages 10 | grep "$CORR_ID"

# 5. Search Elasticsearch
curl -X POST http://localhost:9200/logs-*/_search \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": { \"match\": { \"correlation_id\": \"$CORR_ID\" } }
  }" | jq '.hits.hits[0]._source | {time: .["@timestamp"], msg: .message, domain: .["event.domain"]}'
```

### Service Health Checks

```bash
# All services
make status

# Individual services
curl -s http://localhost:13133/ && echo "OTLP OK"
curl -s http://localhost:5601/api/status | jq '.state' && echo "Kibana OK"
curl -s http://localhost:9200/_cluster/health | jq '.status' && echo "ES OK"
curl -s http://localhost:9600/_node/stats | jq '.pipelines' > /dev/null && echo "Logstash OK"
```
