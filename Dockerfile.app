FROM python:3.12.9-slim

WORKDIR /workspace

# Install uv
RUN pip install --no-cache-dir uv

# Copy project files
COPY . .

# Sync dependencies
RUN uv sync

# Run FastAPI app
CMD ["uv", "run", "uvicorn", "src.fastapi_otel_logging:app", "--host", "0.0.0.0", "--port", "8000"]
