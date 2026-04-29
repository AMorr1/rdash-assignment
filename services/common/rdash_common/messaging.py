import json
from typing import Any

from azure.identity.aio import DefaultAzureCredential
from azure.servicebus import ServiceBusMessage
from azure.servicebus.aio import ServiceBusClient


class EventPublisher:
    def __init__(self, namespace: str, topic: str, connection_string: str | None = None):
        self.namespace = namespace
        self.topic = topic
        self.connection_string = connection_string
        self.client: ServiceBusClient | None = None
        self.credential: DefaultAzureCredential | None = None

    async def connect(self) -> None:
        if self.connection_string:
            self.client = ServiceBusClient.from_connection_string(self.connection_string)
            return
        self.credential = DefaultAzureCredential()
        self.client = ServiceBusClient(
            fully_qualified_namespace=f"{self.namespace}.servicebus.windows.net",
            credential=self.credential,
        )

    async def publish(self, payload: dict[str, Any]) -> None:
        if not self.client:
            raise RuntimeError("publisher not connected")
        async with self.client:
            sender = self.client.get_topic_sender(topic_name=self.topic)
            async with sender:
                await sender.send_messages(ServiceBusMessage(json.dumps(payload)))


class EventConsumer:
    def __init__(
        self,
        namespace: str,
        topic: str,
        subscription: str,
        connection_string: str | None = None,
    ):
        self.namespace = namespace
        self.topic = topic
        self.subscription = subscription
        self.connection_string = connection_string
        self.client: ServiceBusClient | None = None
        self.credential: DefaultAzureCredential | None = None

    async def connect(self) -> None:
        if self.connection_string:
            self.client = ServiceBusClient.from_connection_string(self.connection_string)
            return
        self.credential = DefaultAzureCredential()
        self.client = ServiceBusClient(
            fully_qualified_namespace=f"{self.namespace}.servicebus.windows.net",
            credential=self.credential,
        )

