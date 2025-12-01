import logging
import os
from typing import Callable

from fastapi import FastAPI, Request

from elk_logging import ElasticsearchHandler, build_elasticsearch_client


def configure_logging() -> logging.Logger:
	root = logging.getLogger()
	if any(isinstance(handler, ElasticsearchHandler) for handler in root.handlers):
		return root
	root.setLevel(logging.INFO)
	formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(name)s | %(message)s")
	stream = logging.StreamHandler()
	stream.setFormatter(formatter)
	root.addHandler(stream)
	client = build_elasticsearch_client(
		os.getenv("ELASTICSEARCH_URL", "http://localhost:9200"),
		api_key=os.getenv("ELASTICSEARCH_API_KEY"),
		username=os.getenv("ELASTICSEARCH_USERNAME"),
		password=os.getenv("ELASTICSEARCH_PASSWORD"),
		ca_path=os.getenv("ELASTICSEARCH_CA_CERT"),
	)
	elk_handler = ElasticsearchHandler(client, index=os.getenv("FASTAPI_LOG_INDEX", "fastapi-logs"))
	elk_handler.setFormatter(formatter)
	root.addHandler(elk_handler)
	return root


app = FastAPI(title="FastAPI logging -> ELK demo")
configure_logging()
logger = logging.getLogger("fastapi-demo")


@app.middleware("http")
async def request_logger(request: Request, call_next: Callable):
	response = await call_next(request)
	logger.info(
		"HTTP %s %s -> %s",
		request.method,
		request.url.path,
		response.status_code,
		extra={
			"extra_fields": {
				"demo": "fastapi",
				"path": request.url.path,
				"status_code": response.status_code,
				"client": request.client.host if request.client else "unknown",
			}
		},
	)
	return response


@app.get("/healthz")
async def healthz():
	logger.info("health check hit", extra={"extra_fields": {"demo": "fastapi"}})
	return {"status": "ok"}


if __name__ == "__main__":
	import uvicorn

	uvicorn.run("scripts.backend.fastapi_logging:app", host="0.0.0.0", port=8000, reload=True)
