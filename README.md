# ELK Stack Docker Setup

## Prerequisites
- Docker
- Docker Compose

## Quick Start

1. Start the ELK stack:
```bash
docker-compose up -d
```

2. Check service status:
```bash
docker-compose ps
```

3. Access services:
   - Elasticsearch: http://localhost:9200
   - Kibana: http://localhost:5601
   - Logstash: localhost:5000 (TCP), localhost:5044 (Beats), localhost:8081 (HTTP)

4. Stop the stack:
```bash
docker-compose down
```

5. Stop and remove volumes:
```bash
docker-compose down -v
```

## Configuration

Edit `.env` file to customize:
- Elastic Stack version
- Port mappings
- Heap sizes

## Logs

View logs for specific service:
```bash
docker-compose logs -f elasticsearch
docker-compose logs -f logstash
docker-compose logs -f kibana
```

## Testing

Prerequisites: `curl`, `bash`, and `python3` available on your host.

1. `chmod +x scripts/test-logstash-http.sh`
2. Optionally override targets (`LOGSTASH_HOST`, `LOGSTASH_PORT`, `ES_HOST`, `ES_PORT`, `SLEEP_SECONDS`) and run:
   ```bash
   scripts/test-logstash-http.sh "optional custom message"
   ```
3. The script POSTs a JSON event (with a unique `test_id`) to `localhost:8081`, waits briefly, and queries Elasticsearch for that ID. It exits non-zero if the document is not found so CI can flag ingestion problems.
4. Run `scripts/test-elk-stack.sh` to hit Elasticsearch (`/_cluster/health`), Logstash (`/_node/stats`), Kibana (`/api/status`), and then invoke `scripts/test-logstash-http.sh` to ensure an event flows through the stack. The script exits non-zero if any service fails its health check or the document is not indexed.