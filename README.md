# ELK Stack + OpenTelemetry + Kafka Logging

A production-ready observability stack combining Elasticsearch, Logstash, Kibana with OpenTelemetry integration and Kafka for scalable distributed logging.

## Stack Prerequisites

- **Docker & Docker Compose** - For bundled ELK stack, Kafka, OTLP Collector
- **Optional: Python 3.11+** with [uv](https://docs.astral.sh/uv/getting-started/) for running sample FastAPI application

## Quick Start

### 1. Start All Services

```bash
docker-compose up -d
docker-compose ps
```

### 2. Access Services

| Service | URL | Purpose |
|---------|-----|---------|
| Kibana | http://localhost:5601 | Log visualization & dashboards |
| Elasticsearch | http://localhost:9200 | Log storage & search |
| FastAPI App | http://localhost:8000 | Sample application |
| Kafka UI | http://localhost:8888 | Kafka broker visualization |
| OTLP Collector Health | http://localhost:13133 | Telemetry collection status |
| Logstash API | http://localhost:9600 | Pipeline metrics |

### 3. Stop Services

```bash
docker-compose down        # Stop containers
docker-compose down -v     # Stop and remove volumes
```

## Using Makefile (Recommended)

The Makefile provides convenient shortcuts for all common operations:

```bash
# Infrastructure
make help                  # Show all available commands
make up                    # Start all services
make down                  # Stop services
make down-volumes          # Stop and remove volumes
make ps                    # Show container status
make status                # Check service health
make clean                 # Stop and remove all containers/volumes

# Logging & Monitoring
make logs                  # Tail all service logs
make logs-es               # Tail Elasticsearch logs
make logs-logstash         # Tail Logstash logs
make logs-kibana           # Tail Kibana logs
make logs-kafka            # Tail Kafka logs
make logs-otel             # Tail OTLP Collector logs

# Application Development
make sync                  # Install Python dependencies (uv)
make dev                   # Run FastAPI OTel app locally (port 8000)
make test-fastapi          # Run FastAPI logging app locally

# Testing & Validation
make test-kafka            # Test Kafka connectivity
make test-stack            # Run full integration tests
```

## Configuration

### Environment Variables

Configure services via `.env` file:

```bash
# Elasticsearch/Kibana/Logstash Version
ELASTIC_VERSION=8.10.0

# Memory Allocation
LS_HEAP_SIZE=1g            # Logstash JVM heap
ES_HEAP_SIZE=1g            # Elasticsearch JVM heap

# Service Ports (customize if needed)
ES_PORT=9200
KIBANA_PORT=5601
KAFKA_PORT=9092
LOGSTASH_PORT=5000
```

## Complete Logging Data Flow

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ FastAPI Application (Port 8000)                                 │
│ ├─ HTTP Requests                                                │
│ ├─ Correlation IDs (UUID)                                       │
│ └─ Structured Logging                                           │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ├─ Traces (OTLP/gRPC)
                   ├─ Metrics (OTLP)
                   └─ Logs (OTLP)
                   │
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│ OTLP Collector (Port 4317/4318)                                 │
├─────────────────────────────────────────────────────────────────┤
│ Processors:                                                     │
│ ├─ memory_limiter (512 MiB)                                    │
│ ├─ resourcedetection (env, system)                             │
│ ├─ attributes (service.version, environment)                  │
│ ├─ transform (severity extraction)                            │
│ ├─ probabilistic_sampler (100%)                               │
│ └─ batch (256 items, 2s timeout)                              │
└──────────────────┬──────────────────────────────────────────────┘
                   │
        ┌──────────┼──────────┐
        ↓          ↓          ↓
   Traces      Metrics      Logs
   (Proto)     (Proto)    (Text)
        │          │          │
        └──────────┼──────────┘
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│ Kafka Topics (Port 29092)                                       │
├─────────────────────────────────────────────────────────────────┤
│ ├─ otel-traces (OTLP Proto)                                    │
│ ├─ otel-metrics (OTLP Proto)                                   │
│ └─ otel-logs (Raw Text) ──┐                                    │
└──────────────────────────┼───────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ Logstash (Port 5044)                                            │
├─────────────────────────────────────────────────────────────────┤
│ Input: Kafka (group: logstash-otel-consumer)                   │
│ Filter:                                                         │
│ ├─ Parse text                                                   │
│ ├─ Extract resource attributes                                 │
│ ├─ Extract log body & severity                                 │
│ └─ Map to ECS schema                                            │
│ Output: Elasticsearch                                           │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│ Elasticsearch (Port 9200)                                       │
├─────────────────────────────────────────────────────────────────┤
│ Indices: otel-logs-YYYY.MM.dd                                  │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│ Kibana (Port 5601)                                              │
├─────────────────────────────────────────────────────────────────┤
│ ├─ Discover: Browse & search logs                              │
│ ├─ Visualizations: Charts & dashboards                         │
│ ├─ Alerts: Notification rules                                  │
│ └─ Index Pattern: otel-logs-*                                  │
└─────────────────────────────────────────────────────────────────┘
```

## FastAPI with OpenTelemetry

### Starting the Application

```bash
# Using Makefile (recommended)
make dev

# Or run directly
uv run uvicorn src.fastapi_otel_logging:app --host 0.0.0.0 --port 8000 --reload
```

### Features

✅ Distributed tracing with correlation IDs (UUID per request)  
✅ Structured logging with enriched contextual attributes  
✅ OTLP gRPC exporter for traces, metrics, and logs  
✅ Kafka producer via OTLP Collector for scalable log streaming  
✅ Request/response middleware with HTTP metadata (method, status, latency, client IP)  
✅ Exception tracing with full stack traces and error context  
✅ Resource attributes (service name, version, environment, hostname)  
✅ Automatic instrumentation of FastAPI, requests, logging  
✅ Attribute validation and enrichment with mandatory field enforcement  
✅ PII protection (automatic redaction of sensitive keywords)  
✅ Request correlation tracking across the entire pipeline (FastAPI → OTLP → Kafka → Logstash → Elasticsearch)  
✅ Non-blocking async logging with batch export  

### Available Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/healthz` | Health check endpoint |
| GET | `/api/logs?message=<msg>` | Log a message with optional enrichment headers |
| GET | `/docs` | Swagger API documentation |
| GET | `/redoc` | ReDoc API documentation |

#### GET /healthz
Health check to verify the service is running.
```bash
curl http://localhost:8000/healthz
```

#### GET /api/logs
Log a message with OpenTelemetry instrumentation and automatic correlation tracking.

**Query Parameters:**
- `message` (optional, string): Log message content. Default: `"sample log"`

**Optional Headers (Recommended):**
- `X-Service-Name`: Service name (default: `unknown-service`)
- `X-Service-Version`: Service version (default: `1.0.0`)
- `X-Environment`: Deployment environment - `dev`, `staging`, `prod`, `test` (default: `dev`)
- `X-Log-Level`: Log severity - `DEBUG`, `INFO`, `WARN`, `ERROR`, `CRITICAL`, `FATAL`, `TRACE` (default: `INFO`)
- `X-Event-Type`: Event type - `access`, `error`, `audit`, `validation`, `performance`, `security` (default: `access`)
- `X-Event-Category`: Event category - `application`, `authentication`, `database`, `api`, `security`, `infrastructure` (default: `api`)
- `X-Event-Domain`: Event domain - `auth`, `frontend`, `backend` (default: `backend`)

### Quick API Tests

```bash
# Health check
curl http://localhost:8000/healthz

# Log a message (basic)
curl "http://localhost:8000/api/logs?message=hello%20world"

# Log a message (with all headers)
curl -X GET "http://localhost:8000/api/logs?message=User%20authenticated" \
  -H "X-Service-Name: auth-api" \
  -H "X-Service-Version: 1.0.0" \
  -H "X-Environment: prod" \
  -H "X-Log-Level: INFO" \
  -H "X-Event-Type: audit" \
  -H "X-Event-Category: authentication" \
  -H "X-Event-Domain: auth"

# Capture and display correlation ID
CORR_ID=$(curl -s "http://localhost:8000/api/logs?message=test" | jq -r '.correlation_id')
echo "Correlation ID: $CORR_ID"

# Pretty print response
curl -s "http://localhost:8000/api/logs?message=test" | jq '.'

# Load test (sequential - 5 requests)
for i in {1..5}; do
  curl -s "http://localhost:8000/api/logs?message=load_test_$i"
done

# Load test (parallel - 10 concurrent)
seq 1 10 | xargs -P 10 -I {} curl -s "http://localhost:8000/api/logs?message=concurrent_{}"

# Search logs by correlation ID in Elasticsearch
CORR_ID=$(curl -s "http://localhost:8000/api/logs?message=test" | jq -r '.correlation_id')
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d "{\"query\": {\"match\": {\"correlation_id\": \"$CORR_ID\"}}}" | jq '.hits.hits'
```

### Example Log in Elasticsearch

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

## Testing & Validation

### Health Checks

```bash
# OTLP Collector health
curl http://localhost:13133/

# Elasticsearch cluster health
curl http://localhost:9200/_cluster/health | jq '.'

# Logstash API stats
curl http://localhost:9600/_node/stats | jq '.pipelines'

# Kibana health
curl http://localhost:5601/api/status | jq '.version'
```

### Kafka Operations

```bash
# List topics
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# View otel-logs messages (last 5)
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic otel-logs \
  --max-messages 5 \
  --from-beginning

# Check consumer group lag
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group logstash-otel-consumer \
  --describe
```

### Elasticsearch Queries

```bash
# List indices
curl http://localhost:9200/_cat/indices?v

# Count logs
curl http://localhost:9200/otel-logs-*/_count | jq '.count'

# Search by correlation ID
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match": { "correlation_id": "550e8400-e29b-41d4-a716-446655440000" } },
    "size": 5
  }' | jq '.hits.hits[0]._source'
```

### Running Tests

```bash
# Full integration test
make test-stack

# Test individual components
make test-kafka
make test-fastapi
```

## Troubleshooting

### OTLP Collector Issues

```bash
# Check collector health
curl http://localhost:13133/

# View collector logs
docker-compose logs otel-collector

# Verify network connectivity from collector to Kafka
docker-compose exec otel-collector nc -zv kafka 29092
```

### Kafka Issues

```bash
# Verify topics exist
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# Create missing topic
docker exec kafka kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create \
  --topic otel-logs \
  --partitions 1 \
  --replication-factor 1
```

### Logstash Issues

```bash
# View detailed logs
docker-compose logs logstash | grep -i error | tail -20

# Check Kafka consumer lag
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group logstash-otel-consumer \
  --describe

# Verify Logstash-Kafka connectivity
docker-compose exec logstash nc -zv kafka 29092
```

### Elasticsearch Issues

```bash
# Check cluster status
curl http://localhost:9200/_cluster/health?pretty

# View all indices
curl http://localhost:9200/_cat/indices?v

# Search recent logs
curl -X POST http://localhost:9200/otel-logs-*/_search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "range": { "@timestamp": { "gte": "now-1h" } } },
    "sort": [{ "@timestamp": { "order": "desc" } }],
    "size": 10
  }' | jq '.hits.hits[] | {time: ._source["@timestamp"], msg: ._source.message}'
```

### No Data in Elasticsearch

1. **Verify FastAPI is sending data:**
   ```bash
   curl http://localhost:8000/api/logs?message=test
   ```

2. **Check OTLP Collector:**
   ```bash
   curl http://localhost:13133/
   docker-compose logs otel-collector | grep -i received
   ```

3. **Check Kafka messages:**
   ```bash
   docker exec kafka kafka-console-consumer.sh \
     --bootstrap-server localhost:9092 \
     --topic otel-logs \
     --max-messages 3
   ```

4. **Check Logstash processing:**
   ```bash
   docker-compose logs logstash | grep -i error
   ```

5. **Verify Elasticsearch indices:**
   ```bash
   curl http://localhost:9200/_cat/indices?v | grep otel-logs
   ```

## Monitoring & Logs

### View Logs by Service

```bash
# All services
make logs

# Specific service
docker-compose logs -f elasticsearch
docker-compose logs -f logstash
docker-compose logs -f kibana
docker-compose logs -f kafka
docker-compose logs -f otel-collector
docker-compose logs -f fastapi_app
```

### Performance Metrics

| Component | Setting | Value |
|-----------|---------|-------|
| OTLP Batch | Batch Size | 256 records |
| OTLP Batch | Timeout | 2 seconds |
| OTLP Memory | Limit | 512 MiB |
| Trace Sampling | Rate | 100% (all traces) |
| Logstash Pipeline | Workers | auto (cores) |

## Next Steps

1. **Access Kibana:** http://localhost:5601
2. **Create Index Pattern:** `otel-logs-*` with timestamp field `@timestamp`
3. **Browse Logs:** Go to Discover and explore your logs
4. **Build Dashboards:** Create visualizations of your log data
5. **View Detailed API Documentation:** See [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) for comprehensive endpoint details, validation rules, request/response examples, and troubleshooting guides