import logging
import time

import sentry_sdk
from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from rdash_common.logging import bind_correlation_id

REQUEST_COUNT = Counter(
    "rdash_http_requests_total",
    "Total HTTP requests",
    ["service", "method", "path", "status"],
)
REQUEST_LATENCY = Histogram(
    "rdash_http_request_duration_seconds",
    "HTTP request latency",
    ["service", "method", "path"],
)


def configure_sentry(service_name: str, environment: str, dsn: str | None, traces_rate: float) -> None:
    if not dsn:
        return
    sentry_sdk.init(
        dsn=dsn,
        environment=environment,
        release=f"{service_name}@0.1.0",
        traces_sample_rate=traces_rate,
    )


def install_http_instrumentation(app: FastAPI, service_name: str) -> None:
    logger = logging.getLogger(service_name)

    @app.middleware("http")
    async def correlation_middleware(request: Request, call_next):  # type: ignore[misc]
        correlation_id = bind_correlation_id(request.headers.get("x-correlation-id"))
        start = time.perf_counter()
        path = request.url.path
        try:
            response: Response = await call_next(request)
            return response
        finally:
            elapsed = time.perf_counter() - start
            status = getattr(locals().get("response"), "status_code", 500)
            REQUEST_COUNT.labels(service_name, request.method, path, status).inc()
            REQUEST_LATENCY.labels(service_name, request.method, path).observe(elapsed)
            logger.info(
                "request_completed",
                extra={
                    "method": request.method,
                    "path": path,
                    "status_code": status,
                    "duration_seconds": round(elapsed, 4),
                    "correlation_id": correlation_id,
                },
            )

    @app.get("/metrics", include_in_schema=False)
    async def metrics() -> Response:
        return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

