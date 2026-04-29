from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class CommonSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    service_name: str = Field(default="service")
    environment: str = Field(default="dev")
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = Field(default="INFO")
    sentry_dsn: str | None = Field(default=None)
    sentry_traces_sample_rate: float = Field(default=0.1)

    http_host: str = Field(default="0.0.0.0")
    http_port: int = Field(default=8080)

    redis_url: str = Field(default="redis://localhost:6379/0")
    postgres_primary_dsn: str = Field(default="postgresql://postgres:postgres@localhost:5432/app")
    postgres_replica_dsn: str = Field(default="postgresql://postgres:postgres@localhost:5433/app")

    servicebus_namespace: str = Field(default="localhost")
    servicebus_topic: str = Field(default="rdash-events")
    servicebus_subscription: str = Field(default="worker")
    servicebus_connection_string: str | None = Field(default=None)

    object_storage_account_url: str = Field(default="https://example.blob.core.windows.net")
    object_storage_container: str = Field(default="worker-results")

    registry_base_url: str = Field(default="http://registry:8080")

    user_jwt_issuer: str = Field(default="https://login.example.com/")
    user_jwt_audience: str = Field(default="rdash")
    user_jwt_secret: str = Field(default="development-user-secret")

    service_token_secret: str = Field(default="development-service-secret")
    service_token_issuer: str = Field(default="rdash-core")
    service_token_audience: str = Field(default="rdash-registry")

    cache_ttl_seconds: int = Field(default=60)


@lru_cache(maxsize=1)
def get_settings() -> CommonSettings:
    return CommonSettings()

