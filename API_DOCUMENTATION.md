# FastAPI OpenTelemetry Logging API Documentation

## Overview
FastAPI application with integrated OpenTelemetry tracing and comprehensive structured logging. The application:
- Exports **traces** to OTLP Collector (gRPC)
- Exports **logs** to OTLP Collector → Kafka (JSON encoding)
- Sends **metrics** via OTLP
- Includes **distributed tracing** with correlation IDs
- Implements **HTTP middleware** for automatic request/response logging
- Provides **exception tracking** and error context

## Base URL
```
http://localhost:8000
```

## Architecture

### Request Lifecycle
```
HTTP Request
    ↓
┌─ Middleware (log_requests)
│  ├─ Generate correlation_id (UUID)
│  ├─ Start span: {METHOD} {PATH}
│  ├─ Set span attributes (method, url, client_ip, correlation_id)
│  ├─ Call next() [actual endpoint]
│  ├─ Set span: http.status_code
│  ├─ Log: INFO with http metadata
│  └─ On exception: record_exception(), log ERROR
│
└─ Endpoint Handler
   ├─ Create local span
   ├─ Set endpoint-specific attributes
   ├─ Log: INFO/DEBUG with structured fields
   └─ Return response + metadata
        ↓
    ┌─ Logger Handler (OTLP)
    │  └─ Log Record → OTLP Collector (gRPC) → Kafka
    │
    ├─ Tracer (OTLP)
    │  └─ Span → OTLP Collector (gRPC)
    │
    └─ Response
```

## Endpoints

### 1. Health Check
**GET** `/healthz`

Health check endpoint to verify the service is running and collecting telemetry.

**Request:**
```bash
curl http://localhost:8000/healthz
```

**Response (200 OK):**
```json
{
  "status": "ok"
}
```

**Trace Details:**
- **Span Name:** `healthz`
- **Span Attributes:**
  - `endpoint: /healthz`
- **Log Level:** INFO
- **Log Message:** `Health check`
- **Log Fields:**
  ```json
  {
    "endpoint": "/healthz",
    "status": "ok"
  }
  ```

---

### 2. Log Message
**GET** `/api/logs`

Submit a log message to the system with automatic tracing and correlation.

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `message` | string | No | "sample log" | Log message to record |

**Request:**
```bash
curl "http://localhost:8000/api/logs?message=hello%20world"
```

**Response (200 OK):**
```json
{
  "logged": "hello world",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Trace Details:**
- **Span Name:** `get_logs`
- **Span Attributes:**
  - `correlation_id: <UUID>`
  - `request_message: <message>`
- **Log Level:** INFO
- **Log Message:** `Received log request: {message}`
- **Log Fields:**
  ```json
  {
    "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
    "request_message": "hello world",
    "message_length": 11
  }
  ```

---

## Automatic Middleware Logging

All HTTP requests are automatically logged with comprehensive metadata.

**Middleware: `log_requests`**
- Generates unique `correlation_id` per request
- Creates span: `{METHOD} {PATH}`
- Logs request/response details
- Captures exceptions and traces them

**Example Log Entry (Elasticsearch):**
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
  "http.url": "/api/logs",
  "http.status_code": 200,
  "http.client_ip": "127.0.0.1"
}
```

**On Exception (500 Error):**
```json
{
  "@timestamp": "2024-01-15T10:31:00.456Z",
  "service.name": "fastapi-otel",
  "log.level": "ERROR",
  "message": "Request failed: GET /api/logs",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "http.method": "GET",
  "http.url": "/api/logs",
  "http.status_code": 500,
  "error": "ValueError: Invalid input",
  "stack_trace": "..."
}
```

---

## Log Ingestion Pipeline

### Flow Diagram
```
FastAPI Application
    ↓ (Python logging)
OpenTelemetry LoggingHandler
    ↓ (OTLP/gRPC)
OTLP Collector (Port 4317)
    ├─ Processors:
    │  ├─ memory_limiter (512 MiB limit)
    │  ├─ resourcedetection (env, system)
    │  ├─ attributes (service.version, deployment.environment)
    │  ├─ transform (severity_text → log.level)
    │  ├─ probabilistic_sampler (100% sampling)
    │  └─ batch (256 items, 2s timeout)
    │
    ├─ Kafka Exporter (Signal-Specific Configuration)
    │  ├─ Traces Topic: otel-traces (otlp_proto encoding)
    │  ├─ Metrics Topic: otel-metrics (otlp_proto encoding)
    │  └─ Logs Topic: otel-logs (raw_text encoding)
    │     └─ Brokers: kafka:29092
    │     └─ Protocol: Kafka 2.6.0
    │
    └─ Debug Exporter (STDOUT)
        ↓
    Kafka Broker (Port 29092)
        ├─ Topic: otel-traces
        ├─ Topic: otel-metrics
        └─ Topic: otel-logs
            ├─ Partitions: 1 (auto-created)
            └─ Replication Factor: 1
                ↓
            Logstash Consumer (Port 5044)
                ├─ Input: Kafka (topic: otel-logs, group: logstash-otel-consumer)
                ├─ Filter:
                │  ├─ Parse text (log body as plain text)
                │  ├─ Extract resource attributes
                │  ├─ Extract log body & severity
                │  └─ Map to ECS schema
                │
                └─ Elasticsearch Output
                    └─ Index: otel-logs-YYYY.MM.dd
                        ↓
                    Kibana (Port 5601)
                        ├─ Index Pattern: otel-logs-*
                        ├─ Discover: Browse & search logs
                        ├─ Visualizations: Charts & dashboards
                        └─ Alerts: Notification rules
```

---

## Testing Guide

### Prerequisites
```bash
# Start all services
make up

# Install dependencies
make sync

# Start FastAPI app (in another terminal)
make dev
# Or run directly:
# uv run uvicorn src.fastapi_otel_logging:app --host 0.0.0.0 --port 8000 --reload
```

### Basic Health Checks

**1. Simple health check:**
```bash
curl http://localhost:8000/healthz
```

**2. Health check with verbose output:**
```bash
curl -v http://localhost:8000/healthz
```

**3. Health check with response headers:**
```bash
curl -i http://localhost:8000/healthz
```

**4. Pretty print with jq:**
```bash
curl -s http://localhost:8000/healthz | jq '.'
```

### Log API Tests

**1. Log with default message:**
```bash
curl http://localhost:8000/api/logs
```

**2. Log with custom message:**
```bash
curl "http://localhost:8000/api/logs?message=test%20message%20123"
```

**3. Log with special characters (URL encoded):**
```bash
curl "http://localhost:8000/api/logs?message=Hello%20World%21%20%40%23%24"
```

**4. Log with long message:**
```bash
curl "http://localhost:8000/api/logs?message=$(python -c 'print(\"x\" * 500)')"
```

**5. Capture correlation_id from response:**
```bash
CORR_ID=$(curl -s "http://localhost:8000/api/logs?message=test" | jq -r '.correlation_id')
echo "Correlation ID: $CORR_ID"
```

### Load Testing

**1. Simple load test (10 requests):**
```bash
for i in {1..10}; do
  curl -s "http://localhost:8000/api/logs?message=load_test_$i"
done
```

**2. Parallel load test (20 concurrent):**
```bash
seq 1 20 | xargs -P 10 -I {} curl -s "http://localhost:8000/api/logs?message=concurrent_{}"
```

**3. Load test with timestamps:**
```bash
for i in {1..5}; do
  echo "[$(date)] Request $i"
  curl -s "http://localhost:8000/api/logs?message=test_$i" | jq '.'
  sleep 0.5
done
```

### OTLP Collector Tests

**1. Check OTLP Collector health:**
```bash
curl http://localhost:13133/
```

**2. Check OTLP Collector metrics:**
```bash
curl http://localhost:8888/metrics | head -20
```

**3. View collector logs:**
```bash
docker-compose logs -f otel-collector
```

### Kafka Integration Tests

**1. Check Kafka connectivity:**
```bash
make test-kafka
```

**2. List Kafka topics:**
```bash
docker exec kafka kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list
```

**3. View otel-logs topic messages (last 5):**
```bash
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
  --max-messages 5
```

**4. Monitor Kafka in real-time:**
```bash
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
  --from-beginning \
  --max-messages 0
```

**5. Access Kafka UI (Visual):**
```
http://localhost:8888
```

### Logstash Tests

**1. Check Logstash health:**
```bash
curl http://localhost:9600/_node/stats | jq '.pipelines'
```

**2. View Logstash logs:**
```bash
docker-compose logs -f logstash
```

**3. Check Logstash-Kafka consumer group:**
```bash
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group logstash-otel-consumer \
  --describe
```

### Elasticsearch Tests

**1. Check Elasticsearch cluster health:**
```bash
curl http://localhost:9200/_cluster/health | jq '.'
```

**2. List all indices:**
```bash
curl http://localhost:9200/_cat/indices?v
```

**3. Count documents in otel-logs indices:**
```bash
curl http://localhost:9200/otel-logs-*/_count | jq '.'
```

**4. Search logs by correlation_id:**
```bash
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "match": { "correlation_id": "550e8400-e29b-41d4-a716-446655440000" }
    }
  }' | jq '.hits.hits[0]._source'
```

**5. Search logs by service:**
```bash
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "match": { "service.name": "fastapi-otel" }
    },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 10
  }' | jq '.hits.hits[] | {timestamp: ._source["@timestamp"], message: ._source.message}'
```

**6. Get recent logs (last hour):**
```bash
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "@timestamp": {
          "gte": "now-1h"
        }
      }
    },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 20
  }' | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message, level: ._source["log.level"]}'
```

### Kibana Tests

**1. Access Kibana:**
```
http://localhost:5601
```

**2. Create index pattern:**
- Go to **Stack Management** → **Index Patterns**
- Click **Create index pattern**
- Name: `otel-logs-*`
- Timestamp field: `@timestamp`
- Click **Create index pattern**

**3. Browse logs:**
- Go to **Discover**
- Select `otel-logs-*` index
- View log entries with all fields

**4. Create visualization:**
- Go to **Visualize Library** → **Create new visualization**
- Type: Bar chart (Log level distribution)
- Data view: `otel-logs-*`
- X-axis: `log.level`
- Create

### Full Stack Integration Test

**1. Run complete test:**
```bash
make test-stack
```

**2. Manual end-to-end test:**
```bash
# 1. Generate logs
echo "=== Generating test logs..."
for i in {1..3}; do
  curl -s "http://localhost:8000/api/logs?message=e2e_test_$i" | jq '.'
done

# 2. Check OTLP Collector
echo "=== Checking OTLP Collector..."
curl -s http://localhost:13133/ | head -20

# 3. Check Kafka
echo "=== Checking Kafka topic..."
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
  --max-messages 1

# 4. Check Elasticsearch
echo "=== Checking Elasticsearch..."
curl -s http://localhost:9200/otel-logs-*/_count | jq '.count'

# 5. Check Kibana
echo "=== Kibana available at: http://localhost:5601"
```

---

## Monitoring Commands

**View service status:**
```bash
make status
```

**Tail all logs:**
```bash
make logs
```

**Tail specific service:**
```bash
make logs-logstash
make logs-es
docker-compose logs -f fastapi_app
docker-compose logs -f otel-collector
```

---

## Performance Metrics

**Log Batching (OTLP):**
- Batch size: 256 records
- Timeout: 2 seconds
- Max batch size: 1024 records

**Kafka Producer:**
- Compression: gzip
- Timeout: 30 seconds
- Retry: max 3 attempts, 250ms backoff

**Trace Sampling:**
- Probabilistic sampler: 100% (all traces)
- Memory limit: 512 MiB

---

## Common Issues & Solutions

### Logstash Ruby filter syntax error
**Error:** `Unknown setting 'tag_on_error' for ruby`

**Solution:** The Ruby filter in Logstash doesn't support `tag_on_error`. Error handling is managed internally within the Ruby code block using begin/rescue. The pipeline has been updated to handle errors gracefully:

```bash
# Restart Logstash after update
docker-compose restart logstash

# Verify pipeline started
docker-compose logs logstash | grep -i "pipeline started"
```

### Logstash grok filter syntax error
**Error:** `Unknown setting 'keep_on_failure' for grok`

**Solution:** The correct Logstash grok parameter is `tag_on_failure`, not `keep_on_failure`. The current pipeline uses `json` filter instead of `grok` for better OTLP compatibility.

### Logstash fails to parse JSON from Kafka
**Error:** `json parsing error` or `ECS compatibility warning`

**Solution:** Verify the JSON being sent to Kafka is valid:
```bash
# View raw messages from Kafka
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
  --max-messages 1 \
  --from-beginning

# Check Logstash logs for parsing errors
docker-compose logs logstash | grep -i error

# Restart Logstash if configuration was fixed
docker-compose restart logstash
```

### No logs in Elasticsearch
```bash
# 1. Check OTLP Collector health
curl http://localhost:13133/

# 2. Check Kafka topic and messages
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
  --max-messages 3 \
  --from-beginning

# 3. Check Logstash logs for errors
docker-compose logs logstash | grep -i error | tail -20

# 4. Check Elasticsearch indices
curl http://localhost:9200/_cat/indices?v | grep otel-logs

# 5. Check Logstash-Kafka consumer lag
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group logstash-otel-consumer \
  --describe
```

### OTLP Collector Configuration Error
**Error:** `'auth' has invalid keys: plaintext`, `'compression_codec' has invalid keys`, or `'retry' / 'sasl' has invalid keys`

**Solution:** The OTLP Collector Kafka exporter has a limited set of supported parameters. The configuration has been simplified to use only:
- `brokers`: Kafka broker addresses
- `topic`: Topic name for logs
- `encoding`: Message encoding format (json_lines)
- `protocol_version`: Kafka protocol version

Authentication, retry logic, and compression are handled at the transport level. Restart the collector:
```bash
docker-compose restart otel-collector

# Verify it started successfully
docker-compose logs otel-collector | grep -i "started" | head -5
```

### OTLP Collector Docker daemon connection error
**Error:** `failed to fetch Docker OS type: Cannot connect to the Docker daemon`

**Solution:** The `resourcedetection` processor with Docker detector requires access to the Docker daemon, which isn't available in all containerized environments. The configuration has been updated to use only `env` and `system` detectors which don't require Docker access.

If you need Docker resource detection:
1. Mount the Docker socket: `-v /var/run/docker.sock:/var/run/docker.sock:ro`
2. Or modify the detector list in `otel-collector/config.yml` to include `docker`

Restart the collector:
```bash
docker-compose restart otel-collector

# Verify it started successfully
docker-compose logs otel-collector | grep -i "started"
```
