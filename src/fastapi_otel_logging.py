import logging
import os
import sys
import time
import uuid
from contextlib import asynccontextmanager
from typing import Optional

# Ensure src directory is in path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

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

try:
    from log_attributes_validator import validate_and_enrich_log_record
except ImportError:
    # Fallback if module not found - use simple passthrough
    def validate_and_enrich_log_record(message, attrs):
        return True, attrs, None


# OTEL endpoint configuration - explicit per-signal endpoint
OTEL_TRACES_ENDPOINT = os.getenv(
    "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "otel-collector:4317"
)
OTEL_LOGS_ENDPOINT = os.getenv(
    "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", "otel-collector:4317"
)

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


# Custom LogRecord filter to inject contextual attributes
class AttributeInjectorFilter(logging.Filter):
    """Injects custom attributes into LogRecord for OTEL processing"""

    def __init__(self, attributes_dict):
        super().__init__()
        self.attributes_dict = attributes_dict or {}

    def filter(self, record):
        for key, value in self.attributes_dict.items():
            setattr(record, key, value)
        return True


def get_log_method(logger_instance, level_str):
    """Get the appropriate logger method based on level string"""
    level_str = str(level_str).upper() if level_str else "INFO"
    level_map = {
        "DEBUG": logger_instance.debug,
        "INFO": logger_instance.info,
        "WARNING": logger_instance.warning,
        "WARN": logger_instance.warning,
        "ERROR": logger_instance.error,
        "CRITICAL": logger_instance.critical,
        "FATAL": logger_instance.critical,
    }
    return level_map.get(level_str, logger_instance.info)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("FastAPI service starting up", extra={"event": "startup"})
    yield
    logger.info("FastAPI service shutting down", extra={"event": "shutdown"})


app = FastAPI(lifespan=lifespan)
FastAPIInstrumentor.instrument_app(app)


@app.get("/healthz")
async def healthz():
    with tracer.start_as_current_span("healthz") as span:
        span.set_attribute("endpoint", "/healthz")
        logger.info(
            "Health check",
            extra={"endpoint": "/healthz", "status": "ok"},
        )
        return {"status": "ok"}


@app.get("/api/logs")
async def get_logs(request: Request, message: Optional[str] = "sample log"):
    correlation_id = (
        request.state.correlation_id
        if hasattr(request.state, "correlation_id")
        else str(uuid.uuid4())
    )

    # Get enriched attributes from middleware if available
    service_name = request.headers.get("X-Service-Name", "unknown-service")
    service_version = request.headers.get(
        "X-Service-Version", os.getenv("SERVICE_VERSION", "1.0.0")
    )
    environment = request.headers.get("X-Environment", os.getenv("ENVIRONMENT", "dev"))
    log_level = request.headers.get("X-Log-Level", "INFO")
    event_type = request.headers.get("X-Event-Type", "access")
    event_category = request.headers.get("X-Event-Category", "api")

    # Create attributes dict for OTEL - these will be converted to log record attributes
    custom_attrs = {
        "service.name": service_name,
        "service.version": service_version,
        "deployment.environment": environment,
        "log.level": log_level,
        "event.type": event_type,
        "event.category": event_category,
        "request_message": message,
        "message_length": len(message) if message else 0,
        "correlation_id": correlation_id,
    }

    # Create a temporary logger with the injector filter
    temp_logger = logging.getLogger("api.logs")
    injector = AttributeInjectorFilter(custom_attrs)

    # Remove any existing injectors to avoid duplicates
    temp_logger.filters = [
        f for f in temp_logger.filters if not isinstance(f, AttributeInjectorFilter)
    ]
    temp_logger.addFilter(injector)

    with tracer.start_as_current_span("get_logs") as span:
        span.set_attribute("correlation_id", correlation_id)
        span.set_attribute("request_message", message)
        span.set_attribute("service.name", service_name)
        span.set_attribute("environment", environment)

        # Use the correct log method based on the header
        log_method = get_log_method(temp_logger, log_level)
        log_method(
            f"Received log request: {message}",
            extra=custom_attrs,
        )

        # Remove the filter after logging
        temp_logger.removeFilter(injector)

        return {"logged": message, "correlation_id": correlation_id}


@app.middleware("http")
async def log_requests(request: Request, call_next):
    """
    HTTP middleware with mandatory attribute enrichment and validation
    """
    correlation_id = str(uuid.uuid4())
    request.state.correlation_id = correlation_id
    start_time = time.time()

    # Extract service metadata from headers or use defaults
    service_name = request.headers.get("X-Service-Name", "unknown-service")
    service_version = request.headers.get(
        "X-Service-Version", os.getenv("SERVICE_VERSION", "1.0.0")
    )
    environment = request.headers.get("X-Environment", os.getenv("ENVIRONMENT", "dev"))
    log_level = request.headers.get("X-Log-Level", "INFO")
    event_type = request.headers.get("X-Event-Type", "access")
    event_category = request.headers.get("X-Event-Category", "api")
    event_domain = request.headers.get("X-Event-Domain", "backend")

    # 基礎屬性（會被驗證器補充）
    base_attributes = {
        "service.name": service_name,
        "service.version": service_version,
        "deployment.environment": environment,
        "log.level": log_level,
        "event.domain": event_domain,
        "event.type": event_type,
        "event.category": event_category,
        "trace.id": correlation_id,
        "http.method": request.method,
        "http.path": request.url.path,
        "client.ip": request.client.host if request.client else "unknown",
    }

    # 驗證和補充
    is_valid, enriched_attrs, error = validate_and_enrich_log_record(
        f"{request.method} {request.url.path}", base_attributes
    )

    if not is_valid:
        logger.warning(f"Attribute validation failed: {error}, using defaults")
        enriched_attrs = base_attributes  # 降低標準但繼續處理

    with tracer.start_as_current_span(f"{request.method} {request.url.path}") as span:
        # 設置 span attributes
        for key, value in enriched_attrs.items():
            if isinstance(value, (str, int, float, bool)):
                span.set_attribute(key, value)

        # Create injector for middleware logs
        injector = AttributeInjectorFilter(enriched_attrs)
        middleware_logger = logging.getLogger("middleware")
        middleware_logger.filters = [
            f
            for f in middleware_logger.filters
            if not isinstance(f, AttributeInjectorFilter)
        ]
        middleware_logger.addFilter(injector)

        try:
            response = await call_next(request)
            duration_ms = (time.time() - start_time) * 1000

            # 成功響應
            response_attrs = {
                **enriched_attrs,
                "http.status_code": response.status_code,
                "event.duration_ms": duration_ms,
                "event.outcome": "success" if response.status_code < 400 else "failure",
            }

            span.set_attribute("http.status_code", response.status_code)
            span.set_attribute("http.duration_ms", duration_ms)

            # Use the correct log method based on the header
            log_method = get_log_method(middleware_logger, log_level)
            log_method(
                f"{request.method} {request.url.path} -> {response.status_code}",
                extra=response_attrs,
            )
            middleware_logger.removeFilter(injector)
            return response

        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000

            # 錯誤響應
            error_attrs = {
                **enriched_attrs,
                "http.status_code": 500,
                "event.duration_ms": duration_ms,
                "event.outcome": "error",
                "error.type": type(e).__name__,
                "error.message": str(e),
            }

            span.set_attribute("http.status_code", 500)
            span.set_attribute("error.type", type(e).__name__)
            span.record_exception(e)

            middleware_logger.error(
                f"Request failed: {request.method} {request.url.path}",
                extra=error_attrs,
                exc_info=True,
            )
            middleware_logger.removeFilter(injector)
            raise
