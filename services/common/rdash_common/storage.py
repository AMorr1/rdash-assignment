from azure.identity.aio import DefaultAzureCredential
from azure.storage.blob.aio import BlobServiceClient


class BlobWriter:
    def __init__(self, account_url: str, container: str):
        self.account_url = account_url
        self.container = container
        self.credential = DefaultAzureCredential()
        self.client = BlobServiceClient(account_url=account_url, credential=self.credential)

    async def upload_text(self, blob_name: str, body: str) -> None:
        blob_client = self.client.get_blob_client(container=self.container, blob=blob_name)
        await blob_client.upload_blob(body, overwrite=True)

