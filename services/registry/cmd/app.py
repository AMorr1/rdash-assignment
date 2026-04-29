import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException

from rdash_common.auth import require_user_token, verify_bearer_token
from rdash_common.config import get_settings
from rdash_common.database import PostgresClients
from rdash_common.logging import configure_logging
from rdash_common.telemetry import configure_sentry, install_http_instrumentation

settings = get_settings()
configure_logging(settings.log_level)
configure_sentry(
    settings.service_name,
    settings.environment,
    settings.sentry_dsn,
    settings.sentry_traces_sample_rate,
)
logger = logging.getLogger("registry")

db = PostgresClients(settings.postgres_primary_dsn, settings.postgres_replica_dsn)


@asynccontextmanager
async def lifespan(_: FastAPI):
    await db.connect()
    yield
    await db.close()


app = FastAPI(title="rdash-registry", lifespan=lifespan)
install_http_instrumentation(app, "rdash-registry")


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok", "service": "registry"}


@app.get("/v1/profile")
async def profile(_: dict = Depends(require_user_token)) -> dict:
    return {"status": "ok", "authentication": "edge-validated"}


@app.get("/v1/users/{user_id}")
async def get_user(
    user_id: str,
    authorization: str | None = Header(default=None),
) -> dict:
    verify_bearer_token(
        authorization,
        secret=settings.service_token_secret,
        audience=settings.service_token_audience,
        issuer=settings.service_token_issuer,
    )
    if not db.primary_pool:
        raise HTTPException(status_code=503, detail="primary pool unavailable")
    async with db.primary_pool.acquire() as conn:
        row = await conn.fetchrow(
            "select id, email, display_name, state from users where id = $1",
            user_id,
        )
    if not row:
        logger.warning("user_not_found", extra={"user_id": user_id})
        raise HTTPException(status_code=404, detail="user not found")
    return dict(row)

