import argparse
import logging
import os

from elk_logging import ElasticsearchHandler, build_elasticsearch_client


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Plain Python log shipping demo.")
    parser.add_argument("--es-url", default=os.getenv("ELASTICSEARCH_URL", "http://localhost:9200"))
    parser.add_argument("--index", default=os.getenv("PYTHON_LOG_INDEX", "python-logs"))
    parser.add_argument("--api-key", default=os.getenv("ELASTICSEARCH_API_KEY"))
    parser.add_argument("--username", default=os.getenv("ELASTICSEARCH_USERNAME"))
    parser.add_argument("--password", default=os.getenv("ELASTICSEARCH_PASSWORD"))
    parser.add_argument("--ca-path", default=os.getenv("ELASTICSEARCH_CA_CERT"))
    return parser.parse_args()


def configure_plain_logger(
    es_url: str,
    index: str,
    api_key: str | None,
    username: str | None,
    password: str | None,
    ca_path: str | None,
) -> logging.Logger:
    logger = logging.getLogger("python-to-elk")
    if logger.handlers:
        return logger
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(name)s | %(message)s")
    console = logging.StreamHandler()
    console.setFormatter(formatter)
    client = build_elasticsearch_client(es_url, api_key, username, password, ca_path)
    elk_handler = ElasticsearchHandler(client, index=index)
    elk_handler.setFormatter(formatter)
    logger.addHandler(console)
    logger.addHandler(elk_handler)
    return logger


def main() -> None:
    args = parse_args()
    logger = configure_plain_logger(
        es_url=args.es_url,
        index=args.index,
        api_key=args.api_key,
        username=args.username,
        password=args.password,
        ca_path=args.ca_path,
    )
    logger.info(
        "Plain Python log delivered to ELK index %s",
        args.index,
        extra={"extra_fields": {"demo": "plain-python", "component": "scripts.backend.main"}},
    )
    logger.warning(
        "Alert-level message with extra context",
        extra={
            "extra_fields": {
                "demo": "plain-python",
                "component": "scripts.backend.main",
                "severity": "warning",
            }
        },
    )


if __name__ == "__main__":
    main()
