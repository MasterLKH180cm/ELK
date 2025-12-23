import logging
import os
import uuid
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Request
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

# OTEL endpoint configuration - explicit per-signal endpoint
OTEL_TRACES_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "otel-collector:4317")
OTEL_LOGS_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", "otel-collector:4317")

# OpenTelemetry setup with ECS fields
trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=OTEL_TRACES_ENDPOINT, insecure=True))
)

logger_provider = LoggerProvider(
    resource=Resource.create(
        {
            "service.name": "fastapi-otel",
            "service.instance.id": os.getenv("HOSTNAME", "instance-1"),
            "service.version": os.getenv("SERVICE_VERSION", "1.0.0"),
            "deployment.environment": os.getenv("ENVIRONMENT", "development"),
            "host.name": os.getenv("HOSTNAME", "unknown"),
        }
    ),
)
set_logger_provider(logger_provider)

exporter = OTLPLogExporter(endpoint=OTEL_LOGS_ENDPOINT, insecure=True)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(exporter))
handler = LoggingHandler(level=logging.NOTSET, logger_provider=logger_provider)

logging.getLogger().setLevel(logging.INFO)
logging.getLogger().addHandler(handler)

# Instrument libraries
RequestsInstrumentor().instrument()
LoggingInstrumentor().instrument()

tracer = trace.get_tracer(__name__)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        "FastAPI service starting up", extra={"extra_fields": {"event": "startup"}}
    )
    yield
    logger.info(
        "FastAPI service shutting down", extra={"extra_fields": {"event": "shutdown"}}
    )


app = FastAPI(lifespan=lifespan)
FastAPIInstrumentor.instrument_app(app)


@app.get("/healthz")
async def healthz():
    with tracer.start_as_current_span("healthz") as span:
        span.set_attribute("endpoint", "/healthz")
        logger.info(
            "Health check",
            extra={"extra_fields": {"endpoint": "/healthz", "status": "ok"}},
        )
        return {"status": "ok"}


@app.get("/api/logs")
async def get_logs(message: Optional[str] = "sample log"):
    correlation_id = str(uuid.uuid4())
    with tracer.start_as_current_span("get_logs") as span:
        span.set_attribute("correlation_id", correlation_id)
        span.set_attribute("request_message", message)
        logger.info(
            f"Received log request: {message}",
            extra={
                "extra_fields": {
                    "correlation_id": correlation_id,
                    "request_message": message,
                    "message_length": len(message) if message else 0,
                }
            },
        )
        return {"logged": message, "correlation_id": correlation_id}


@app.middleware("http")
async def log_requests(request: Request, call_next):
    correlation_id = str(uuid.uuid4())
    request.state.correlation_id = correlation_id

    with tracer.start_as_current_span(f"{request.method} {request.url.path}") as span:
        span.set_attribute("http.method", request.method)
        span.set_attribute("http.url", str(request.url.path))
        span.set_attribute(
            "http.client_ip", request.client.host if request.client else "unknown"
        )
        span.set_attribute("correlation_id", correlation_id)

        try:
            response = await call_next(request)
            span.set_attribute("http.status_code", response.status_code)
            logger.info(
                f"{request.method} {request.url.path}",
                extra={
                    "extra_fields": {
                        "correlation_id": correlation_id,
                        "http.method": request.method,
                        "http.url": str(request.url.path),
                        "http.status_code": response.status_code,
                        "http.client_ip": request.client.host
                        if request.client
                        else "unknown",
                    }
                },
            )
            return response
        except Exception as e:
            span.set_attribute("http.status_code", 500)
            span.record_exception(e)
            logger.error(
                f"Request failed: {request.method} {request.url.path}",
                extra={
                    "extra_fields": {
                        "correlation_id": correlation_id,
                        "http.method": request.method,
                        "http.url": str(request.url.path),
                        "error": str(e),
                    }
                },
                exc_info=True,
            )
            raise
