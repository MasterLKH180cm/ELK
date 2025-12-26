"""
Log Attributes Validator & Enricher
- Enforces mandatory attributes
- Strips forbidden keywords
- Enriches with domain/event metadata
"""

import logging
import os
from enum import Enum
from typing import Any, Dict, Tuple

logger = logging.getLogger(__name__)


class LogLevel(str, Enum):
    """OpenTelemetry SeverityNumber standard"""

    FATAL = "FATAL"
    ERROR = "ERROR"
    WARN = "WARN"
    INFO = "INFO"
    DEBUG = "DEBUG"
    TRACE = "TRACE"


class EventDomain(str, Enum):
    """允許的業務或技術領域"""

    AUTH = "auth"
    SESSION = "session"
    DICTATION_FRONTEND = "dictation_frontend"
    DICTATION_BACKEND = "dictation_backend"
    WORKLIST = "worklist"
    VIEWER = "viewer"


class EventType(str, Enum):
    """允許的事件類型"""

    ACCESS = "access"
    ERROR = "error"
    AUDIT = "audit"
    VALIDATION = "validation"
    PERFORMANCE = "performance"
    SECURITY = "security"


class EventCategory(str, Enum):
    """允許的技術分類"""

    FRONTEND = "frontend"
    AUTHENTICATION = "authentication"
    DATABASE = "database"
    BACKEND = "backend"
    SECURITY = "security"
    INFRASTRUCTURE = "infrastructure"


class LogAttributesValidator:
    """強制日誌屬性契約"""

    # 必須欄位
    MANDATORY_ATTRIBUTES = [
        "service.name",
        "deployment.environment",
        "log.level",
        "event.domain",
        "event.type",
    ]

    # 禁止關鍵字
    FORBIDDEN_KEYWORDS = [
        "password",
        "secret",
        "token",
        "api_key",
        "credit_card",
        "ssn",
        "national_id",
    ]

    # 有效的環境值
    VALID_ENVIRONMENTS = ["prod", "staging", "dev", "test"]

    @staticmethod
    def validate_attributes(
        attributes: Dict[str, Any],
    ) -> Tuple[bool, str, Dict[str, Any]]:
        """
        驗證並淨化日誌屬性

        Returns:
            (is_valid, error_message, cleaned_attributes)
        """
        cleaned = attributes.copy() if attributes else {}

        # 1. 檢查必須欄位
        for attr in LogAttributesValidator.MANDATORY_ATTRIBUTES:
            if attr not in cleaned or not cleaned[attr]:
                return False, f"Missing mandatory attribute: {attr}", cleaned

        # 2. 驗證 log.level
        try:
            log_level = cleaned.get("log.level")
            if log_level not in [e.value for e in LogLevel]:
                return False, f"Invalid log.level: {log_level}", cleaned
        except Exception as e:
            return False, f"Failed to validate log.level: {str(e)}", cleaned

        # 3. 驗證 deployment.environment
        env = cleaned.get("deployment.environment")
        if env not in LogAttributesValidator.VALID_ENVIRONMENTS:
            return False, f"Invalid deployment.environment: {env}", cleaned

        # 4. 驗證 event.domain
        try:
            event_domain = cleaned.get("event.domain")
            if event_domain not in [e.value for e in EventDomain]:
                return False, f"Invalid event.domain: {event_domain}", cleaned
        except Exception as e:
            return False, f"Failed to validate event.domain: {str(e)}", cleaned

        # 5. 驗證 event.type
        try:
            event_type = cleaned.get("event.type")
            if event_type not in [e.value for e in EventType]:
                return False, f"Invalid event.type: {event_type}", cleaned
        except Exception as e:
            return False, f"Failed to validate event.type: {str(e)}", cleaned

        # 6. 檢查禁止關鍵字（在整個 attributes 值中）
        attributes_str = str(cleaned).lower()
        for keyword in LogAttributesValidator.FORBIDDEN_KEYWORDS:
            if keyword.lower() in attributes_str:
                return False, f"Forbidden keyword detected: {keyword}", cleaned

        return True, "", cleaned

    @staticmethod
    def strip_pii(text: str) -> str:
        """移除或遮蔽潛在的 PII 資料"""
        import re

        # 簡單的信用卡號遮蔽
        text = re.sub(r"\b(?:\d{4}[-\s]?){3}\d{4}\b", "[REDACTED_CARD]", text)

        # 簡單的 email 遮蔽
        text = re.sub(
            r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",
            "[REDACTED_EMAIL]",
            text,
        )

        # 簡單的電話號碼遮蔽（台灣格式）
        text = re.sub(r"\b09\d{8}\b", "[REDACTED_PHONE]", text)

        return text


class LogAttributesEnricher:
    """自動補充日誌屬性"""

    @staticmethod
    def enrich_from_service_context(attributes: Dict[str, Any]) -> Dict[str, Any]:
        """
        從環境和上下文補充屬性
        """
        enriched = attributes.copy() if attributes else {}

        # 補充服務名稱（若未提供）
        if "service.name" not in enriched:
            enriched["service.name"] = os.getenv("OTEL_SERVICE_NAME", "unknown-service")

        # 補充環境
        if "deployment.environment" not in enriched:
            enriched["deployment.environment"] = os.getenv("ENVIRONMENT", "dev")

        # 補充版本
        if "service.version" not in enriched:
            enriched["service.version"] = os.getenv("SERVICE_VERSION", "0.0.0")

        # 補充主機名
        if "host.name" not in enriched:
            enriched["host.name"] = os.getenv("HOSTNAME", "unknown-host")

        # 補充 namespace（若未提供）
        if "service.namespace" not in enriched:
            enriched["service.namespace"] = LogAttributesEnricher._infer_namespace(
                enriched.get("service.name", "")
            )

        # 補充 event.category（若未提供）
        if "event.category" not in enriched and "event.domain" in enriched:
            enriched["event.category"] = LogAttributesEnricher._infer_category(
                enriched.get("event.domain", "")
            )

        return enriched

    @staticmethod
    def _infer_namespace(service_name: str) -> str:
        """根據 service.name 推斷 namespace"""
        mapping = {
            "auth": "identity",
            "session": "identity",
            "dictation_frontend": "frontend",
            "dictation_backend": "backend",
            "worklist": "frontend",
            "viewer": "frontend",
        }

        for key, value in mapping.items():
            if key in service_name.lower():
                return value

        return "unknown"

    @staticmethod
    def _infer_category(event_domain: str) -> str:
        """根據 event.domain 推斷 event.category"""
        mapping = {
            "auth": "authentication",
            "session": "backend",
            "dictation_frontend": "frontend",
            "dictation_backend": "backend",
            "worklist": "frontend",
            "viewer": "frontend",
        }
        return mapping.get(event_domain, "frontend")


def validate_and_enrich_log_record(
    log_body: str, attributes: Dict[str, Any]
) -> Tuple[bool, Dict[str, Any], str]:
    """
    完整的驗證和補充流程

    Returns:
        (is_valid, enriched_attributes, error_message)
    """
    # 1. 補充缺失的屬性
    enriched = LogAttributesEnricher.enrich_from_service_context(attributes)

    # 2. 驗證必須欄位和值
    is_valid, error_msg, cleaned = LogAttributesValidator.validate_attributes(enriched)

    if not is_valid:
        logger.warning(f"Log validation failed: {error_msg}")
        return False, cleaned, error_msg

    # 3. 在 log body 中檢查禁止關鍵字
    if any(
        keyword.lower() in log_body.lower()
        for keyword in LogAttributesValidator.FORBIDDEN_KEYWORDS
    ):
        logger.warning("Log body contains forbidden keywords")
        # 注意：不拒絕，但要遮蔽
        sanitized_body = LogAttributesValidator.strip_pii(log_body)
        logger.warning(f"Log body sanitized: {sanitized_body}")

    return True, cleaned, ""


if __name__ == "__main__":
    # 測試
    test_attrs = {
        "service.name": "auth-api",
        "deployment.environment": "prod",
        "log.level": "INFO",
        "event.domain": "auth",
        "event.type": "access",
    }

    is_valid, enriched, error = validate_and_enrich_log_record("Test log", test_attrs)
    print(f"Valid: {is_valid}")
    print(f"Enriched: {enriched}")
    if error:
        print(f"Error: {error}")
