import json
import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException

from rdash_common.auth import mint_service_token
from rdash_common.cache import new_redis_client
from rdash_common.config import get_settings
from rdash_common.database import PostgresClients
from rdash_common.logging import configure_logging
from rdash_common.messaging import EventPublisher
from rdash_common.telemetry import configure_sentry, install_http_instrumentation

settings = get_settings()
configure_logging(settings.log_level)
configure_sentry(
    settings.service_name,
    settings.environment,
    settings.sentry_dsn,
    settings.sentry_traces_sample_rate,
)
logger = logging.getLogger("core")

db = PostgresClients(settings.postgres_primary_dsn, settings.postgres_replica_dsn)
redis = new_redis_client(settings.redis_url)
publisher = EventPublisher(
    settings.servicebus_namespace,
    settings.servicebus_topic,
    settings.servicebus_connection_string,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    await db.connect()
    await publisher.connect()
    yield
    await db.close()
    await redis.close()


app = FastAPI(title="rdash-core", lifespan=lifespan)
install_http_instrumentation(app, "rdash-core")


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok", "service": "core"}


@app.get("/v1/tasks/{task_id}")
async def get_task(task_id: str) -> dict:
    cache_key = f"task:{task_id}"
    if cached := await redis.get(cache_key):
        return json.loads(cached)

    if not db.replica_pool:
        raise HTTPException(status_code=503, detail="replica pool unavailable")
    async with db.replica_pool.acquire() as conn:
        row = await conn.fetchrow(
            "select id, status, payload from tasks where id = $1",
            task_id,
        )
    if not row:
        raise HTTPException(status_code=404, detail="task not found")
    result = {"id": row["id"], "status": row["status"], "payload": row["payload"]}
    await redis.set(cache_key, json.dumps(result), ex=settings.cache_ttl_seconds)
    return result


@app.post("/v1/tasks")
async def create_task(body: dict) -> dict:
    if not db.primary_pool:
        raise HTTPException(status_code=503, detail="primary pool unavailable")

    async with db.primary_pool.acquire() as conn:
        row = await conn.fetchrow(
            "insert into tasks(payload, status) values($1, 'queued') returning id, status, payload",
            json.dumps(body),
        )
    payload = {"task_id": row["id"], "action": "process-task"}
    await publisher.publish(payload)
    logger.info("task_enqueued", extra={"task_id": row["id"]})
    return {"id": row["id"], "status": row["status"], "payload": row["payload"]}


@app.get("/v1/registry/users/{user_id}")
async def get_registry_user(user_id: str) -> dict:
    token = mint_service_token(
        settings.service_token_secret,
        settings.service_token_issuer,
        settings.service_token_audience,
    )
    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(
            f"{settings.registry_base_url}/v1/users/{user_id}",
            headers={"Authorization": f"Bearer {token}"},
        )
    response.raise_for_status()
    return response.json()

