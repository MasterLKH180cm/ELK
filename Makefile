.PHONY: help up down logs sync run-otel run-fastapi test-kafka clean ps status kafka-health kafka-topics kafka-consumer kafka-monitor

help:
	@echo "ELK Stack + Kafka + FastAPI OTel Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make up              - Start all Docker services (ELK + Kafka + Zookeeper)"
	@echo "  make down            - Stop all Docker services"
	@echo "  make down-volumes    - Stop services and remove volumes"
	@echo "  make ps              - Show running containers status"
	@echo "  make logs            - Tail logs from all services"
	@echo "  make logs-es         - Tail Elasticsearch logs"
	@echo "  make logs-logstash   - Tail Logstash logs"
	@echo "  make logs-kibana     - Tail Kibana logs"
	@echo "  make logs-kafka      - Tail Kafka logs"
	@echo "  make sync            - Run 'uv sync' to install dependencies"
	@echo "  make run-otel        - Start FastAPI OTel app (port 8000)"
	@echo "  make run-fastapi     - Start FastAPI logging app (port 8000)"
	@echo "  make test-kafka      - Test Kafka connectivity"
	@echo "  make kafka-health    - Check detailed Kafka health status"
	@echo "  make kafka-topics    - List all Kafka topics"
	@echo "  make kafka-consumer  - Consume messages from fastapi-logs topic"
	@echo "  make kafka-monitor   - Monitor Kafka health + consumer lag continuously"
	@echo "  make test-stack      - Run full ELK stack tests"
	@echo "  make clean           - Remove all containers and volumes"
	@echo "  make status          - Check service health status"

up:
	docker-compose up -d
	@echo "✓ Services started. Wait 30s for health checks..."
	@sleep 30
	@make status

down:
	docker-compose down

down-volumes:
	docker-compose down -v
	@echo "✓ Services stopped and volumes removed"

ps:
	docker-compose ps

status:
	@echo "=== Service Health Status ==="
	@docker-compose ps
	@echo ""
	@echo "=== Elasticsearch ==="
	@curl -s http://localhost:9200/_cluster/health | jq '.status' || echo "❌ Not responding"
	@echo ""
	@echo "=== Kibana ==="
	@curl -s http://localhost:5601/api/status | jq '.state' || echo "❌ Not responding"
	@echo ""
	@echo "=== Logstash ==="
	@curl -s http://localhost:9600/_node/stats | jq '.jvm.pid' || echo "❌ Not responding"
	@echo ""
	@echo "=== Kafka ==="
	@docker exec kafka kafka-broker-api-versions.sh --bootstrap-server kafka:29092 > /dev/null 2>&1 && echo "✓ Kafka ready" || echo "❌ Not responding"

logs:
	docker-compose logs -f

logs-es:
	docker-compose logs -f elasticsearch

logs-logstash:
	docker-compose logs -f logstash

logs-kibana:
	docker-compose logs -f kibana

logs-kafka:
	docker-compose logs -f kafka

sync:
	uv sync
	@echo "✓ Dependencies installed"

dev: sync
	@echo "Starting FastAPI OTel app on http://localhost:8000"
	uv run uvicorn src.fastapi_otel_logging:app --host 0.0.0.0 --port 8000 --reload

test-fastapi: sync
	@echo "Starting FastAPI logging app on http://localhost:8000"
	uv run uvicorn scripts.backend.fastapi_logging:app --host 0.0.0.0 --port 8000 --reload

test-kafka:
	@echo "Testing Kafka connectivity..."
	@docker exec kafka kafka-broker-api-versions.sh --bootstrap-server kafka:29092 > /dev/null 2>&1 && echo "✓ Kafka test passed" || echo "❌ Kafka test failed"

kafka-health:
	@echo "=== Kafka Container Health ==="
	@docker inspect --format='{{json .State.Health}}' kafka | jq '.' || echo "❌ Cannot inspect kafka container"
	@echo ""
	@echo "=== Kafka Broker API Versions ==="
	@docker exec kafka kafka-broker-api-versions.sh --bootstrap-server kafka:29092 | head -5 || echo "❌ Broker not responding"
	@echo ""
	@echo "=== Kafka Topics ==="
	@docker exec kafka kafka-topics.sh --bootstrap-server kafka:29092 --list || echo "❌ Cannot list topics"

kafka-topics:
	@echo "Listing Kafka topics..."
	@docker exec kafka kafka-topics.sh --bootstrap-server kafka:29092 --list

kafka-consumer:
	@echo "Consuming messages from fastapi-logs topic..."
	@docker exec kafka kafka-console-consumer.sh --bootstrap-server kafka:29092 --topic fastapi-logs --from-beginning

kafka-monitor:
	@echo "Monitoring Kafka health & consumer lag (Ctrl+C to stop)..."
	@while true; do \
		clear; \
		echo "=== Kafka Health Monitor ==="; \
		echo "Time: $$(date '+%Y-%m-%d %H:%M:%S')"; \
		echo ""; \
		echo "--- Broker Status ---"; \
		docker exec kafka kafka-broker-api-versions.sh --bootstrap-server kafka:29092 2>&1 | head -3 || echo "❌ Broker down"; \
		echo ""; \
		echo "--- Topics ---"; \
		docker exec kafka kafka-topics.sh --bootstrap-server kafka:29092 --list 2>&1 || echo "❌ Cannot list topics"; \
		echo ""; \
		echo "--- Consumer Groups ---"; \
		docker exec kafka kafka-consumer-groups.sh --bootstrap-server kafka:29092 --list 2>&1 || echo "❌ Cannot list consumer groups"; \
		echo ""; \
		echo "--- Logstash Consumer Lag ---"; \
		docker exec kafka kafka-consumer-groups.sh --bootstrap-server kafka:29092 --describe --group logstash-group 2>&1 || echo "⚠️  No logstash-group yet"; \
		echo ""; \
		echo "(Refreshing every 10s, Ctrl+C to exit)"; \
		sleep 10; \
	done

test-stack: up
	@echo "Running full ELK stack tests..."
	@echo "1. Testing Elasticsearch..."
	@curl -s http://localhost:9200/_cluster/health | jq '.' || echo "❌ Elasticsearch failed"
	@echo ""
	@echo "2. Testing Logstash..."
	@curl -s http://localhost:9600/_node/stats | jq '.' || echo "❌ Logstash failed"
	@echo ""
	@echo "3. Testing Kibana..."
	@curl -s http://localhost:5601/api/status | jq '.' || echo "❌ Kibana failed"
	@echo ""
	@echo "4. Running HTTP Logstash test..."
	@bash src/test-logstash-http.sh "makefile test message" || echo "❌ HTTP test failed"

clean:
	docker-compose down -v
	@echo "✓ All containers and volumes removed"

.DEFAULT_GOAL := help
