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

1. Run `scripts/test-logstash-http.sh` (or pass a JSON string as the first argument) to POST a sample event to the HTTP input on port 8081.
2. Watch `docker-compose logs -f logstash` or check Kibana Discover to confirm the document arrived.