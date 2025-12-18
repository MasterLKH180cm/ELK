import logging
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from elasticsearch import Elasticsearch
from elasticsearch import exceptions as es_exceptions
try:
	from elastic_transport import TransportError
except ImportError:  # graceful fallback if elastic-transport is absent
	class TransportError(Exception):
		...
_ELASTIC_EXCEPTIONS = tuple(
	exc
	for exc in (
		getattr(es_exceptions, "ApiError", None),
		getattr(es_exceptions, "ConnectionError", None),
		getattr(es_exceptions, "SerializationError", None),
		getattr(es_exceptions, "TransportError", None),
		TransportError,
	)
	if isinstance(exc, type) and issubclass(exc, BaseException)
) or (Exception,)


def build_elasticsearch_client(
	es_url: str,
	api_key: Optional[str] = None,
	username: Optional[str] = None,
	password: Optional[str] = None,
	ca_path: Optional[str] = None,
) -> Elasticsearch:
	config: Dict[str, Any] = {}
	if api_key:
		config["api_key"] = api_key
	elif username:
		config["basic_auth"] = (username, password or "")
	if ca_path:
		config["ca_certs"] = ca_path
	return Elasticsearch(es_url, **config)


class ElasticsearchHandler(logging.Handler):
	def __init__(self, client: Elasticsearch, index: str, level: int = logging.INFO) -> None:
		super().__init__(level)
		self.client = client
		self.index = index

	def emit(self, record: logging.LogRecord) -> None:
		document = self._serialize_record(record)
		try:
			self.client.index(index=self.index, document=document)
		except _ELASTIC_EXCEPTIONS as exc:
			logging.getLogger("elk-handler").error("ELK ingest failed: %s", exc)

	def _serialize_record(self, record: logging.LogRecord) -> Dict[str, Any]:
		payload: Dict[str, Any] = {
			"@timestamp": datetime.now(timezone.utc).isoformat(),
			"logger": record.name,
			"level": record.levelname,
			"message": record.getMessage(),
		}
		extra_fields = record.__dict__.get("extra_fields")
		if isinstance(extra_fields, dict):
			payload.update(extra_fields)
		return payload
