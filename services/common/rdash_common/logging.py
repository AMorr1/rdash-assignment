import logging
import sys
import uuid
from contextvars import ContextVar

from pythonjsonlogger import jsonlogger

correlation_id_var: ContextVar[str] = ContextVar("correlation_id", default="-")


class CorrelationIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.correlation_id = correlation_id_var.get()
        return True


def configure_logging(level: str) -> None:
    root = logging.getLogger()
    root.setLevel(level)
    root.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    formatter = jsonlogger.JsonFormatter(
        "%(asctime)s %(levelname)s %(name)s %(message)s %(correlation_id)s"
    )
    handler.setFormatter(formatter)
    handler.addFilter(CorrelationIdFilter())
    root.addHandler(handler)


def bind_correlation_id(value: str | None = None) -> str:
    correlation_id = value or str(uuid.uuid4())
    correlation_id_var.set(correlation_id)
    return correlation_id

