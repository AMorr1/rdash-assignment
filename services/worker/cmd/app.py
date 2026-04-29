import asyncio
import json
import logging
from contextlib import asynccontextmanager

import httpx
from azure.servicebus.aio import AutoLockRenewer
from fastapi import FastAPI

from rdash_common.auth import mint_service_token
from rdash_common.cache import new_redis_client
from rdash_common.config import get_settings
from rdash_common.logging import configure_logging
from rdash_common.messaging import EventConsumer
from rdash_common.storage import BlobWriter
from rdash_common.telemetry import configure_sentry, install_http_instrumentation

settings = get_settings()
configure_logging(settings.log_level)
configure_sentry(
    settings.service_name,
    settings.environment,
    settings.sentry_dsn,
    settings.sentry_traces_sample_rate,
)
logger = logging.getLogger("worker")

redis = new_redis_client(settings.redis_url)
consumer = EventConsumer(
    settings.servicebus_namespace,
    settings.servicebus_topic,
    settings.servicebus_subscription,
    settings.servicebus_connection_string,
)
blob_writer = BlobWriter(settings.object_storage_account_url, settings.object_storage_container)


async def worker_loop() -> None:
    await consumer.connect()
    if not consumer.client:
        raise RuntimeError("consumer unavailable")
    async with consumer.client:
        receiver = consumer.client.get_subscription_receiver(
            topic_name=settings.servicebus_topic,
            subscription_name=settings.servicebus_subscription,
            max_wait_time=10,
            auto_lock_renewer=AutoLockRenewer(),
        )
        async with receiver:
            while True:
                messages = await receiver.receive_messages(max_message_count=10, max_wait_time=5)
                for message in messages:
                    body = b"".join([chunk for chunk in message.body]).decode()
                    event = json.loads(body)
                    await process_event(event)
                    await receiver.complete_message(message)


async def process_event(event: dict) -> None:
    task_id = event["task_id"]
    token = mint_service_token(
        settings.service_token_secret,
        settings.service_token_issuer,
        settings.service_token_audience,
    )
    cached_task = await redis.get(f"task:{task_id}")
    async with httpx.AsyncClient(timeout=5.0) as client:
        registry_resp = await client.get(
            f"{settings.registry_base_url}/v1/users/system",
            headers={"Authorization": f"Bearer {token}"},
        )
        registry_resp.raise_for_status()
    output = {
        "task_id": task_id,
        "registry": registry_resp.json(),
        "cache_hit": bool(cached_task),
    }
    await blob_writer.upload_text(f"{task_id}.json", json.dumps(output))
    logger.info("task_processed", extra=output)


@asynccontextmanager
async def lifespan(_: FastAPI):
    task = asyncio.create_task(worker_loop())
    yield
    task.cancel()
    await redis.close()


app = FastAPI(title="rdash-worker", lifespan=lifespan)
install_http_instrumentation(app, "rdash-worker")


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok", "service": "worker"}

