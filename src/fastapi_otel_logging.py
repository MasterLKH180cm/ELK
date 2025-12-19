import json
import logging
import os
from typing import Optional

from fastapi import FastAPI, Request
from kafka import KafkaProducer
from kafka.errors import KafkaError
from opentelemetry import trace
from opentelemetry._logs import set_logger_provider
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Kafka setup
kafka_producer = None
KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092").split(
    ","
)
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "fastapi-logs")


def init_kafka_producer():
    global kafka_producer
    try:
        kafka_producer = KafkaProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            retries=3,
            request_timeout_ms=10000,
            acks=1,
            max_request_size=1048576,
            compression_type="gzip",
        )
        # Test connection
        kafka_producer.send(KAFKA_TOPIC, {"status": "producer_initialized"}).get(
            timeout=5
        )
        logging.info(f"Kafka producer connected to {KAFKA_BOOTSTRAP_SERVERS}")
    except KafkaError as e:
        logging.error(f"Failed to initialize Kafka producer: {e}")
        kafka_producer = None
    except Exception as e:
        logging.error(f"Unexpected error initializing Kafka producer: {e}")
        kafka_producer = None


# OpenTelemetry setup
trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint="http://localhost:4317"))
)

logger_provider = LoggerProvider(
    resource=Resource.create(
        {
            "service.name": "fastapi-otel",
            "service.instance.id": "instance-1",
        }
    ),
)
set_logger_provider(logger_provider)

exporter = OTLPLogExporter(insecure=True)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(exporter))
handler = LoggingHandler(level=logging.NOTSET, logger_provider=logger_provider)

logging.getLogger().setLevel(logging.NOTSET)
logging.getLogger().addHandler(handler)

# Instrument libraries
FastAPIInstrumentor.instrument_app(app := FastAPI())
RequestsInstrumentor().instrument()
LoggingInstrumentor().instrument()

tracer = trace.get_tracer(__name__)
logger = logging.getLogger(__name__)


# Custom Kafka handler for logs
class KafkaLogHandler(logging.Handler):
    def emit(self, record):
        # Kafka producer disabled due to protocol issues
        # Logs are sent directly to Elasticsearch via OpenTelemetry
        pass


kafka_handler = KafkaLogHandler()
kafka_handler.setFormatter(logging.Formatter("%(asctime)s"))
logger.addHandler(kafka_handler)
logger.setLevel(logging.INFO)


@app.get("/healthz")
async def healthz():
    with tracer.start_as_current_span("healthz"):
        logger.info("Health check", extra={"extra_fields": {"endpoint": "/healthz"}})
        return {"status": "ok", "kafka_connected": kafka_producer is not None}


@app.get("/api/logs")
async def get_logs(message: Optional[str] = "sample log"):
    with tracer.start_as_current_span("get_logs"):
        logger.info(
            f"Received log request: {message}",
            extra={"extra_fields": {"request_message": message}},
        )
        return {"logged": message}


@app.middleware("http")
async def log_requests(request: Request, call_next):
    with tracer.start_as_current_span(f"{request.method} {request.url.path}"):
        response = await call_next(request)
        logger.info(
            f"{request.method} {request.url.path}",
            extra={
                "extra_fields": {
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "client": request.client.host if request.client else "unknown",
                }
            },
        )
        return response


@app.on_event("startup")
def startup_event():
    init_kafka_producer()


@app.on_event("shutdown")
def shutdown_event():
    if kafka_producer:
        kafka_producer.close()
