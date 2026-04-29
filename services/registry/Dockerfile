FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY services/common /app/services/common
COPY services/registry /app/services/registry

ENV PYTHONPATH=/app/services/common

CMD ["uvicorn", "services.registry.cmd.app:app", "--host", "0.0.0.0", "--port", "8080"]

