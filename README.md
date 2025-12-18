# ELK Stack + Logging Samples

## Stack Prerequisites
- Docker & Docker Compose (for the bundled ELK stack + Kafka)
- Optional local Python toolchain with [uv](https://docs.astral.sh/uv/getting-started/) for the sample apps

## Quick Start (Docker ELK + Kafka)
```bash
docker-compose up -d
docker-compose ps
```
Access services:
- Elasticsearch: http://elasticsearch:9200
- Kibana: http://localhost:5601
- Logstash: localhost:5000 (TCP), localhost:5044 (Beats), localhost:8081 (HTTP)
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
make status            # Check service health
make logs              # Tail all service logs
make run-otel          # Start FastAPI OTel app
make test-stack        # Run full integration tests
make clean             # Stop and remove all containers/volumes
```
See `Makefile` for additional commands like `make logs-kafka`, `make logs-logstash`, etc.

## Configuration & Logs
- Tweak `.env` for Elastic version, port mappings, heap sizes.
- Tail logs per service:
  ```bash
  docker-compose logs -f elasticsearch
  docker-compose logs -f logstash
  docker-compose logs -f kibana
  docker-compose logs -f kafka
  ```

## Stack Testing Helpers
1. `chmod +x test_scripts/test-logstash-http.sh`
2. Optional overrides (`LOGSTASH_HOST`, `LOGSTASH_PORT`, `ES_HOST`, `ES_PORT`, `SLEEP_SECONDS`) then run:
   ```bash
   test_scripts/test-logstash-http.sh "optional custom message"
   ```
   Posts a document via Logstash HTTP input and verifies it in Elasticsearch.
3. `test_scripts/test-elk-stack.sh` checks Elasticsearch (`/_cluster/health`), Logstash (`/_node/stats`), Kibana (`/api/status`), then runs the HTTP test to ensure end-to-end ingestion.
4. Or use Makefile: `make test-stack` for automated testing.

## uv-Based Logging Samples
Run `uv sync` in the repo root first (or `make sync`), then choose any scenario below.

### 1. Plain Python → ELK
```bash
uv run python test_scripts/backend/main.py \
  --es-url http://localhost:9200 \
  --index python-logs
```
All CLI flags have env var counterparts (`ELASTICSEARCH_URL`, `ELASTICSEARCH_API_KEY`, etc.). Each invocation emits structured INFO/WARN events with `extra_fields`.

### 2. FastAPI Logging → ELK
```bash
uv run uvicorn test_scripts.backend.fastapi_logging:app --host 0.0.0.0 --port 8000 --reload
```
Or use Makefile: `make run-fastapi`

Request/response middleware enriches logs (path, status, client IP) and ships them into `FASTAPI_LOG_INDEX` (default `fastapi-logs`). Hit `GET /healthz` for sample entries.

### 3. FastAPI OpenTelemetry → Kafka → ELK
```bash
uv run uvicorn src.backend.fastapi_otel_logging:app --host 0.0.0.0 --port 8000 --reload
```
Or use Makefile: `make run-otel`

Fully OpenTelemetry-compliant FastAPI app that:
- Traces all requests with distributed tracing context
- Exports logs to Kafka topic `fastapi-logs`
- Logstash consumes from Kafka and indexes into Elasticsearch
- Hit `GET /healthz` or `GET /api/logs?message=test` to generate logs
- View traces and logs in Kibana with index pattern `fastapi-otel-logs-*`

### 4. Docker Logs → ELK
```bash
cd docker
docker compose up -d
```
- `app`: runs the FastAPI sample under uv.
- `filebeat`: tails `/var/lib/docker/containers/*/*.log`, adds container metadata, and forwards everything to Elasticsearch.
Inspect data in Kibana Discover using `docker-*`, `fastapi-logs`, or `python-logs` index patterns.