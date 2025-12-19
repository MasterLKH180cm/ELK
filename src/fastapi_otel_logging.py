import logging
import os
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

# OTLP endpoint configuration
OTEL_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")

# OpenTelemetry setup with ECS fields
trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=OTEL_ENDPOINT))
)

logger_provider = LoggerProvider(
    resource=Resource.create(
        {
            "service.name": "fastapi-otel",
            "service.instance.id": "instance-1",
            "service.version": os.getenv("SERVICE_VERSION", "1.0.0"),
            "deployment.environment": os.getenv("ENVIRONMENT", "development"),
            "host.name": os.getenv("HOSTNAME", "unknown"),
        }
    ),
)
set_logger_provider(logger_provider)

exporter = OTLPLogExporter(endpoint=OTEL_ENDPOINT, insecure=True)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(exporter))
handler = LoggingHandler(level=logging.NOTSET, logger_provider=logger_provider)

logging.getLogger().setLevel(logging.INFO)
logging.getLogger().addHandler(handler)

# Instrument libraries
FastAPIInstrumentor.instrument_app(app := FastAPI())
RequestsInstrumentor().instrument()
LoggingInstrumentor().instrument()

tracer = trace.get_tracer(__name__)
logger = logging.getLogger(__name__)


@app.get("/healthz")
async def healthz():
    with tracer.start_as_current_span("healthz"):
        logger.info("Health check", extra={"extra_fields": {"endpoint": "/healthz"}})
        return {"status": "ok"}


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
    with tracer.start_as_current_span(f"{request.method} {request.url.path}") as span:
        response = await call_next(request)
        span.set_attribute("http.method", request.method)
        span.set_attribute("http.url", str(request.url.path))
        span.set_attribute("http.status_code", response.status_code)
        span.set_attribute(
            "client.ip", request.client.host if request.client else "unknown"
        )
        logger.info(
            f"{request.method} {request.url.path}",
            extra={
                "extra_fields": {
                    "http.method": request.method,
                    "http.url": str(request.url.path),
                    "http.status_code": response.status_code,
                    "client.ip": request.client.host if request.client else "unknown",
                }
            },
        )
        return response


@app.on_event("startup")
def startup_event():
    logger.info("FastAPI service starting up")


@app.on_event("shutdown")
def shutdown_event():
    logger.info("FastAPI service shutting down")
