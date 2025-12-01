# ELK Stack + Logging Samples

## Stack Prerequisites
- Docker & Docker Compose (for the bundled ELK stack)
- Optional local Python toolchain with [uv](https://docs.astral.sh/uv/getting-started/) for the sample apps

## Quick Start (Docker ELK)
```bash
docker-compose up -d
docker-compose ps
```
Access services:
- Elasticsearch: http://elasticsearch:9200
- Kibana: http://localhost:5601
- Logstash: localhost:5000 (TCP), localhost:5044 (Beats), localhost:8081 (HTTP)

Shutdown:
```bash
docker-compose down        # stop
docker-compose down -v     # stop + remove volumes
```

## Configuration & Logs
- Tweak `.env` for Elastic version, port mappings, heap sizes.
- Tail logs per service:
  ```bash
  docker-compose logs -f elasticsearch
  docker-compose logs -f logstash
  docker-compose logs -f kibana
  ```

## Stack Testing Helpers
1. `chmod +x scripts/test-logstash-http.sh`
2. Optional overrides (`LOGSTASH_HOST`, `LOGSTASH_PORT`, `ES_HOST`, `ES_PORT`, `SLEEP_SECONDS`) then run:
   ```bash
   scripts/test-logstash-http.sh "optional custom message"
   ```
   Posts a document via Logstash HTTP input and verifies it in Elasticsearch.
3. `scripts/test-elk-stack.sh` checks Elasticsearch (`/_cluster/health`), Logstash (`/_node/stats`), Kibana (`/api/status`), then runs the HTTP test to ensure end-to-end ingestion.

## uv-Based Logging Samples
Run `uv sync` in the repo root first, then choose any scenario below.

### 1. Plain Python → ELK
```bash
uv run python scripts/backend/main.py \
  --es-url http://localhost:9200 \
  --index python-logs
```
All CLI flags have env var counterparts (`ELASTICSEARCH_URL`, `ELASTICSEARCH_API_KEY`, etc.). Each invocation emits structured INFO/WARN events with `extra_fields`.

### 2. FastAPI Logging → ELK
```bash
uv run uvicorn scripts.backend.fastapi_logging:app --host 0.0.0.0 --port 8000 --reload
```
Request/response middleware enriches logs (path, status, client IP) and ships them into `FASTAPI_LOG_INDEX` (default `fastapi-logs`). Hit `GET /healthz` for sample entries.

### 3. Docker Logs → ELK
```bash
cd docker
docker compose up -d
```
- `app`: runs the FastAPI sample under uv.
- `filebeat`: tails `/var/lib/docker/containers/*/*.log`, adds container metadata, and forwards everything to Elasticsearch.
Inspect data in Kibana Discover using `docker-*`, `fastapi-logs`, or `python-logs` index patterns.