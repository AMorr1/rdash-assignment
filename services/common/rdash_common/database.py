import asyncpg


class PostgresClients:
    def __init__(self, primary_dsn: str, replica_dsn: str):
        self.primary_dsn = primary_dsn
        self.replica_dsn = replica_dsn
        self.primary_pool: asyncpg.Pool | None = None
        self.replica_pool: asyncpg.Pool | None = None

    async def connect(self) -> None:
        self.primary_pool = await asyncpg.create_pool(dsn=self.primary_dsn, min_size=1, max_size=5)
        self.replica_pool = await asyncpg.create_pool(dsn=self.replica_dsn, min_size=1, max_size=5)

    async def close(self) -> None:
        if self.primary_pool:
            await self.primary_pool.close()
        if self.replica_pool:
            await self.replica_pool.close()

