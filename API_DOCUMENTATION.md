# FastAPI OpenTelemetry Logging API Documentation

## Overview
FastAPI application with integrated OpenTelemetry tracing and Kafka logging. Traces are exported to OTLP endpoint and logs are sent to both OTLP and Kafka.

## Base URL
```
http://localhost:8000
```

## Endpoints

### 1. Health Check
**GET** `/healthz`

Health check endpoint to verify the service is running.

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

**Trace Span:** `healthz`
**Log Fields:** `endpoint: /healthz`

---

### 2. Log Message
**GET** `/api/logs`

Submit a log message to the system.

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
  "logged": "hello world"
}
```

**Trace Span:** `get_logs`
**Log Fields:** `request_message: <message>`

---

## Middleware Logging

All HTTP requests are automatically logged with the following information:
- HTTP method
- Request path
- Response status code
- Client IP address

**Example Log Entry (Kafka):**
```json
{
  "timestamp": "2024-01-15 10:30:45",
  "level": "INFO",
  "logger": "__main__",
  "message": "GET /api/logs",
  "module": "fastapi_otel_logging",
  "function": "log_requests",
  "line": 92,
  "extra": {
    "method": "GET",
    "path": "/api/logs",
    "status_code": 200,
    "client": "127.0.0.1"
  }
}
```

---

## Test Commands

### Prerequisites
```bash
# Start all services
make up

# Install dependencies
make sync

# Start the FastAPI app (in another terminal)
make dev
```

### Basic Health Tests

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

**4. Log with multiline message:**
```bash
curl "http://localhost:8000/api/logs?message=line1%0Aline2%0Aline3"
```

### Advanced Testing with jq

**1. Pretty print response:**
```bash
curl -s http://localhost:8000/healthz | jq '.'
```

**2. Extract specific field:**
```bash
curl -s http://localhost:8000/healthz | jq '.status'
```

**3. Test multiple endpoints:**
```bash
for i in {1..5}; do
  curl -s "http://localhost:8000/api/logs?message=test_$i" | jq '.logged'
done
```

### Load Testing

**1. Simple load test (10 requests):**
```bash
for i in {1..10}; do
  curl -s "http://localhost:8000/api/logs?message=load_test_$i"
done
```

**2. Load test with timing:**
```bash
for i in {1..20}; do
  time curl -s "http://localhost:8000/api/logs?message=timed_test_$i" > /dev/null
done
```

**3. Concurrent requests (requires GNU Parallel or xargs):**
```bash
seq 1 50 | xargs -P 10 -I {} curl -s "http://localhost:8000/api/logs?message=concurrent_{}"
```

### Kafka Testing

**1. Check Kafka connectivity:**
```bash
make test-kafka
```

**2. View Kafka messages (console consumer):**
```bash
# docker exec kafka kafka-console-consumer.sh \
#   --bootstrap-server localhost:9092 \
#   --topic fastapi-logs \
#   --from-beginning
docker exec kafka-tools kafka-console-consumer.sh \
  --bootstrap-server kafka:29092 \
  --topic fastapi-logs \
  --from-beginning
```

**3. View recent 5 messages:**
```bash
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic fastapi-logs \
  --max-messages 5
```

### Elasticsearch & Kibana Testing

**1. Check Elasticsearch health:**
```bash
curl http://localhost:9200/_cluster/health | jq '.'
```

**2. List indices:**
```bash
curl http://localhost:9200/_cat/indices?v
```

**3. Search logs:**
```bash
curl -X POST http://localhost:9200/logstash-*/_search -H 'Content-Type: application/json' -d '{ "query": { "match": { "message": "GET" } } }' | jq '.'
```

**4. Access Kibana UI:**
```
http://localhost:5601
```

### Trace Testing

**1. View traces (OTLP Collector endpoint):**
```bash
curl http://localhost:4317/api/traces
```

**2. Generate traces with endpoints:**
```bash
# Generate healthz trace
curl http://localhost:8000/healthz

# Generate get_logs trace with message
curl "http://localhost:8000/api/logs?message=trace_test"
```

### Full Stack Test

**1. Run comprehensive stack test:**
```bash
make test-stack
```

**2. Check all service health:**
```bash
make status
```

### Monitoring & Logs

**1. View all service logs:**
```bash
make logs
```

**2. View FastAPI app logs:**
```bash
docker-compose logs -f fastapi_app
```

**3. View Logstash logs:**
```bash
make logs-logstash
```

**4. View Elasticsearch logs:**
```bash
make logs-es
```

---

## Integration Flow

```
FastAPI Request
    ↓
├─→ Trace (OTLP Exporter)
│   └─→ OTLP Collector
│       └─→ Jaeger/Tempo (traces)
│
├─→ Log (Python logging)
│   ├─→ KafkaLogHandler
│   │   └─→ Kafka Topic: "fastapi-logs"
│   │       └─→ Logstash
│   │           └─→ Elasticsearch
│   │               └─→ Kibana (visualization)
│   │
│   └─→ LoggingHandler (OTLP)
│       └─→ OTLP Collector
│           └─→ Loki/OTLP Backend
│
└─→ HTTP Response
```

---

## Error Handling

**Invalid message parameter:**
```bash
curl "http://localhost:8000/api/logs?message="
```

**Nonexistent endpoint:**
```bash
curl http://localhost:8000/notfound
# Returns 404 with FastAPI error response
```

**Server errors are automatically traced and logged.**

---

## Performance Notes

- Traces are batched (BatchSpanProcessor)
- Logs are batched (BatchLogRecordProcessor)
- Kafka producer is async-compatible
- All operations are non-blocking
