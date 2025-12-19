#!/bin/bash
# Consume messages from Kafka topic

TOPIC=${1:-fastapi-logs}
FROM_BEGINNING=${2:---from-beginning}

docker exec kafka /opt/confluent/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic "$TOPIC" \
  "$FROM_BEGINNING"
