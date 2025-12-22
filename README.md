# ELK Stack + OpenTelemetry + Kafka Logging

## Stack Prerequisites
- Docker & Docker Compose (for the bundled ELK stack + Kafka + OTLP Collector)
- Optional local Python toolchain with [uv](https://docs.astral.sh/uv/getting-started/) for the sample apps

## Quick Start (Docker ELK + Kafka + OTLP)
```bash
docker-compose up -d
docker-compose ps
```

Access services:
- Elasticsearch: http://localhost:9200
- Kibana: http://localhost:5601
- OTLP Collector: localhost:4317 (gRPC), localhost:4318 (HTTP)
- Logstash: localhost:5000 (TCP), localhost:5044 (Beats), localhost:8080-8081 (HTTP), localhost:9600 (API)
- Kafka UI: http://localhost:8888
- Kafka: localhost:9092
- Zookeeper: localhost:2181

Shutdown:
```bash
docker-compose down        # stop
docker-compose down -v     # stop + remove volumes
```

## Using Makefile (Recommended)
For convenience, use the included Makefile for common tasks:
```bash
make help              # Show all available commands
make up                # Start all services
make down              # Stop services
make down-volumes      # Stop and remove volumes
make ps                # Show container status
make status            # Check service health
make logs              # Tail all service logs
make logs-es           # Tail Elasticsearch logs
make logs-logstash     # Tail Logstash logs
make logs-kibana       # Tail Kibana logs
make logs-kafka        # Tail Kafka logs
make logs-otel         # Tail OTLP Collector logs
make sync              # Install uv dependencies
make dev               # Run FastAPI OTel app locally
make test-fastapi      # Run FastAPI logging app locally
make test-kafka        # Test Kafka connectivity
make test-stack        # Run full integration tests
make clean             # Stop and remove all containers/volumes
```

## Configuration & Logs
- Tweak `.env` for Elastic version, port mappings, heap sizes, Java memory allocation.
- Tail logs per service:
  ```bash
  docker-compose logs -f elasticsearch
  docker-compose logs -f logstash
  docker-compose logs -f kibana
  docker-compose logs -f kafka
  docker-compose logs -f otel-collector
  ```

## Logging Data Flow

### Complete Flow: FastAPI → OTLP Collector → Kafka → Logstash → Elasticsearch

```
FastAPI Application (Port 8000)
    ├─ Traces (OTLP/gRPC) ──┐
    ├─ Metrics (OTLP)       │
    └─ Logs (OTLP)          ↓
                    OTLP Collector (Port 4317/4318)
                    ├─ Processors:
                    │  ├─ memory_limiter (512 MiB)
                    │  ├─ resourcedetection (env, system)
                    │  ├─ attributes (service version, environment)
                    │  ├─ transform (log level extraction)
                    │  ├─ probabilistic_sampler (100%)
                    │  └─ batch (256 items, 2s timeout)
                    │
                    └─ Kafka Exporter (Signal-specific topics & encoding)
                        ├─ Traces → otel-traces (otlp_proto)
                        ├─ Metrics → otel-metrics (otlp_proto)
                        └─ Logs → otel-logs (raw_text)
                                              ↓
                        Kafka Topics (Port 29092)
                        ├─ otel-traces
                        ├─ otel-metrics
                        └─ otel-logs ──→ Logstash Consumer
                                            ├─ Input: Kafka (group: logstash-otel-consumer)
                                            ├─ Filter:
                                            │  ├─ Parse text
                                            │  ├─ Extract resource attributes
                                            │  ├─ Extract log body & severity
                                            │  └─ Map to ECS schema
                                            │
                                            └─ Output: Elasticsearch (Port 9200)
                                                └─ Index: otel-logs-YYYY.MM.dd
                                                    ↓
                                                Kibana (Port 5601)
```

## Stack Testing Helpers
1. `chmod +x test_scripts/test-logstash-http.sh`
2. Optional overrides (`LOGSTASH_HOST`, `LOGSTASH_PORT`, `ES_HOST`, `ES_PORT`, `SLEEP_SECONDS`) then run:
   ```bash
   test_scripts/test-logstash-http.sh "optional custom message"
   ```
3. `test_scripts/test-elk-stack.sh` checks Elasticsearch (`/_cluster/health`), Logstash (`/_node/stats`), Kibana (`/api/status`).
4. Or use Makefile: `make test-stack` for automated testing.

## FastAPI OpenTelemetry Logging

### 3. FastAPI with OpenTelemetry → Kafka → ELK
```bash
uv run uvicorn src.fastapi_otel_logging:app --host 0.0.0.0 --port 8000 --reload
```
Or use Makefile: `make dev`

**Features:**
- ✅ Distributed tracing with correlation IDs (UUID per request)
- ✅ Structured logging with extra fields
- ✅ OTLP gRPC exporter for traces, metrics, and logs
- ✅ Kafka producer via OTLP Collector
- ✅ Request/response middleware with HTTP metadata
- ✅ Exception tracing and error logging
- ✅ Resource attributes (service name, version, environment, hostname)
- ✅ Automatic instrumentation of FastAPI, requests, logging libraries

**Endpoints:**
- `GET /healthz` - Health check
- `GET /api/logs?message=<msg>` - Log a message

**Sample Requests:**
```bash
# Health check
curl http://localhost:8000/healthz

# Log a message
curl "http://localhost:8000/api/logs?message=test%20message"

# View in Kibana
# Index: otel-logs-*
# Correlation ID: In response and logs for request tracking
```

### Log Structure in Elasticsearch

**Example Log Document:**
```json
{
  "@timestamp": "2024-01-15T10:30:45.123Z",
  "service.name": "fastapi-otel",
  "service.version": "1.0.0",
  "service.instance.id": "instance-1",
  "deployment.environment": "development",
  "host.name": "docker-host",
  "log.level": "INFO",
  "message": "Received log request: test message",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "request_message": "test message",
  "message_length": 12
}
```

## Quick Access URLs
- **Kibana**: http://localhost:5601
- **Elasticsearch**: http://localhost:9200
- **FastAPI App**: http://localhost:8000
- **Kafka UI**: http://localhost:8888
- **OTLP Collector Health**: http://localhost:13133
- **Logstash API**: http://localhost:9600/_node/stats
- **Kafka**: localhost:9092
- **Zookeeper**: localhost:2181

## Environment Variables

### FastAPI App (.env or docker-compose)
| Variable | Default | Description |
|----------|---------|-------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector:4317` | OTLP Collector endpoint |
| `SERVICE_VERSION` | `1.0.0` | Service version in traces/logs |
| `ENVIRONMENT` | `development` | Deployment environment |
| `ELASTICSEARCH_URL` | `http://elasticsearch:9200` | Elasticsearch connection |
| `KAFKA_BOOTSTRAP_SERVERS` | `kafka:29092` | Kafka broker address |

### Docker Compose (.env)
| Variable | Default | Description |
|----------|---------|-------------|
| `ELASTIC_VERSION` | `8.10.0` | Elasticsearch/Kibana/Logstash version |
| `LS_HEAP_SIZE` | `1g` | Logstash JVM heap size |

## Monitoring & Logs

**1. View all service logs:**
```bash
make logs
```

**2. View specific service:**
```bash
docker-compose logs -f fastapi_app
docker-compose logs -f logstash
docker-compose logs -f otel-collector
```

**3. Check OTLP Collector health:**
```bash
curl http://localhost:13133/
```

**4. Check Kafka messages:**
```bash
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server kafka:29092 \
  --topic otel-logs \
  --from-beginning \
  --max-messages 5
```

## Troubleshooting

### OTLP Collector not receiving data
```bash
# Check collector health
curl http://localhost:13133/

# View collector logs
docker-compose logs otel-collector

# Verify FastAPI can reach collector
docker-compose exec app curl http://otel-collector:4317
```

### Kafka topics not created
```bash
# List topics
docker exec kafka kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list

# Create topic manually
docker exec kafka kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create \
  --topic otel-logs \
  --partitions 1 \
  --replication-factor 1
```

### Logstash not consuming from Kafka
```bash
# Check Logstash logs
docker-compose logs logstash

# Verify Kafka connectivity from Logstash
docker-compose exec logstash nc -zv kafka 29092
```

### No data in Elasticsearch
```bash
# Check indices
curl http://localhost:9200/_cat/indices?v

# Search for recent logs
curl http://localhost:9200/otel-logs-*/_search?sort=@timestamp:desc&size=5

# View Kibana: http://localhost:5601
# Create index pattern: otel-logs-*
```