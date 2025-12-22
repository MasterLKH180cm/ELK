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
    ↓ (Python stdlib logging)
OpenTelemetry LoggingHandler
    ↓ (OTLP/gRPC on localhost:4317)
OTLP Collector
    ├─ Receivers: otlp (gRPC on 4317, HTTP on 4318)
    │
    ├─ Processors:
    │  ├─ memory_limiter (512 MiB)
    │  ├─ resourcedetection (env, system)
    │  ├─ attributes (service.*, deployment.*)
    │  ├─ transform (log level mapping)
    │  ├─ probabilistic_sampler (100%)
    │  └─ batch (256 items, 2s timeout)
    │
    ├─ Exporters:
    │  ├─ kafka (logs → otel-logs topic)
    │  ├─ kafka (traces → otel-traces topic)
    │  ├─ kafka (metrics → otel-metrics topic)
    │  └─ debug (STDOUT logging)
    │
    └─ Extensions: health_check (localhost:13133)

    ↓
Kafka Broker (localhost:29092)
    ├─ Topic: otel-logs (partitions: 1)
    ├─ Topic: otel-traces (partitions: 1)
    └─ Topic: otel-metrics (partitions: 1)

    ↓
Logstash Consumer
    ├─ Input: Kafka (otel-logs, group: logstash-otel-consumer)
    ├─ Filter: Parse, enrich, map to ECS
    └─ Output: Elasticsearch (otel-logs-YYYY.MM.dd)

    ↓
Elasticsearch (localhost:9200)
    └─ Indices: otel-logs-2024.01.15, otel-logs-2024.01.16, ...

    ↓
Kibana (localhost:5601)
    ├─ Discover: Search & browse logs
    ├─ Visualizations: Charts & graphs
    └─ Dashboards: Custom monitoring views
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

### 2. Log Message

**Endpoint:** `GET /api/logs`

Submit a log message with automatic tracing, correlation tracking, and metadata enrichment.

#### Request

```bash
curl "http://localhost:8000/api/logs?message=hello%20world"
```

#### Query Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `message` | string | No | `"sample log"` | The message to log |

#### Request Examples

```bash
# Default message
curl http://localhost:8000/api/logs

# Custom message
curl "http://localhost:8000/api/logs?message=hello%20world"

# Long message (URL encoded)
curl "http://localhost:8000/api/logs?message=$(echo%20'This%20is%20a%20longer%20message')"

# Special characters
curl "http://localhost:8000/api/logs?message=Error%20%40%20Step%202%21"

# With jq (pretty print)
curl -s "http://localhost:8000/api/logs?message=test" | jq '.'

# Capture correlation ID
CORR_ID=$(curl -s "http://localhost:8000/api/logs?message=test" | jq -r '.correlation_id')
echo "Correlation ID: $CORR_ID"
```

#### Response

```json
{
  "logged": "hello world",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**HTTP Status:** 200 OK

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `logged` | string | The message that was logged |
| `correlation_id` | UUID | Unique request tracking ID |

#### Telemetry Details

| Attribute | Value |
|-----------|-------|
| Span Name | `get_logs` |
| Log Level | INFO |
| Log Message | `Received log request: {message}` |

#### Span Attributes

```json
{
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "request_message": "hello world",
  "message_length": 11
}
```

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
  "message": "Received log request: hello world",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "request_message": "hello world",
  "message_length": 11
}
```

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

# View otel-logs messages (last 5)
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
  --max-messages 5

# Monitor real-time messages
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
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
curl http://localhost:9200/otel-logs-*/_count | jq '.count'

# Count logs from last hour
curl -X POST http://localhost:9200/otel-logs-*/_search \
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

# Search by correlation_id
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": { \"match\": { \"correlation_id\": \"$CORR_ID\" } },
    \"size\": 10
  }" | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message}'
```

#### By Service

```bash
# Search by service name
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match": { "service.name": "fastapi-otel" } },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 10
  }' | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message, level: ._source["log.level"]}'
```

#### By Log Level

```bash
# Search ERROR logs
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match": { "log.level": "ERROR" } },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 20
  }' | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message}'
```

#### Recent Logs

```bash
# Get last 20 logs (last hour)
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "range": { "@timestamp": { "gte": "now-1h" } } },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 20
  }' | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message, level: ._source["log.level"]}'
```

### Kibana Setup

1. **Access Kibana**
   - Open: http://localhost:5601

2. **Create Index Pattern**
   - Navigate: **Stack Management** → **Index Patterns**
   - Click: **Create index pattern**
   - Name: `otel-logs-*`
   - Timestamp field: `@timestamp`
   - Click: **Create index pattern**

3. **Browse Logs**
   - Navigate: **Discover**
   - Select: `otel-logs-*` index
   - View all log entries with fields

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
curl -s http://localhost:9200/otel-logs-*/_count | jq '.count'

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
   docker exec kafka kafka-console-consumer.sh \
     --bootstrap-server localhost:9092 \
     --topic otel-logs \
     --max-messages 3 \
     --from-beginning
   ```

4. **Check Logstash errors:**
   ```bash
   docker-compose logs logstash | grep -i error
   ```

5. **Check Elasticsearch:**
   ```bash
   curl http://localhost:9200/_cat/indices?v | grep otel-logs
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

# 4. Check Kafka message
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
  --max-messages 10 | grep "$CORR_ID"

# 5. Search Elasticsearch
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": { \"match\": { \"correlation_id\": \"$CORR_ID\" } }
  }" | jq '.hits.hits[0]._source'
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
